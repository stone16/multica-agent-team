#!/usr/bin/env bash
# pr-sweep.sh — deterministic filter that dispatches code-review work to
# Hao (Senior Engineer) and Dustin (Security & Performance Reviewer).
#
# Pipeline:
#   1. Enumerate open PRs across all non-archived stone16/* repos
#   2. For each PR, read sentinel state from PR comments
#   3. Decide what's needed:
#        - converged (consensus / debate sentinel for current SHA) → skip
#        - docs-only diff → write consensus:approve sentinel directly, skip
#        - both reviewed at this SHA → compute consensus and write sentinel
#        - only one reviewed → enqueue the other
#        - neither reviewed → enqueue both
#   4. If queues non-empty, create one Multica issue per agent with the PR list
#
# No LLM is invoked here. Hao / Dustin only run when the queues actually have work.

set -euo pipefail

GH_OWNER="${GH_OWNER:-stone16}"
HAO_AGENT="${HAO_AGENT:-Hao}"
DUSTIN_AGENT="${DUSTIN_AGENT:-Dustin}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IGNORE_FILE="$REPO_ROOT/.pr-sweep-ignore"

log() { printf '%s\n' "$*" >&2; }

# ---------- Ignore list ----------

is_repo_ignored() {
  local repo="$1"
  [[ -f "$IGNORE_FILE" ]] || return 1
  grep -vE '^[[:space:]]*(#|$)' "$IGNORE_FILE" \
    | tr -d '[:space:]' \
    | grep -Fxq "$repo"
}

# ---------- GitHub helpers ----------

list_repos() {
  gh repo list "$GH_OWNER" --limit 200 --no-archived --json name --jq '.[].name'
}

list_open_prs() {
  # Outputs tab-separated: number<TAB>headRefOid<TAB>authorLogin
  gh pr list --repo "$GH_OWNER/$1" --state open --limit 100 \
    --json number,headRefOid,author \
    --jq '.[] | "\(.number)\t\(.headRefOid)\t\(.author.login)"'
}

pr_comments_body() {
  gh pr view "$2" --repo "$GH_OWNER/$1" --json comments \
    --jq '.comments[].body' 2>/dev/null || true
}

pr_changed_files() {
  gh pr diff "$2" --repo "$GH_OWNER/$1" --name-only 2>/dev/null || true
}

post_pr_comment() {
  local body="$3"
  printf '%s' "$body" | gh pr comment "$2" --repo "$GH_OWNER/$1" --body-file -
}

# ---------- Sentinel parsing ----------

# Returns the verdict word if a sentinel matching <name>: <sha> verdict: <v>
# exists in the body, else empty.
sentinel_verdict() {
  local body="$1" name="$2" sha="$3"
  printf '%s' "$body" \
    | grep -oE "${name}:[[:space:]]*${sha}[[:space:]]+verdict:[[:space:]]*[a-z-]+" \
    | tail -1 \
    | sed -E "s/.*verdict:[[:space:]]*([a-z-]+).*/\1/"
}

has_final_sentinel() {
  local body="$1" sha="$2"
  printf '%s' "$body" | grep -qE "(consensus|debate):[[:space:]]*${sha}\\b"
}

# ---------- Filters ----------

# True if every changed file is documentation. Lets us skip code-review on
# pure-doc PRs.
is_docs_only() {
  local repo="$1" num="$2"
  local files
  files=$(pr_changed_files "$repo" "$num")
  [[ -n "$files" ]] || return 1
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$f" in
      *.md|*.markdown|*.txt|*.rst|*.adoc|docs/*|*/docs/*|.github/*.md) ;;
      *) return 1 ;;
    esac
  done <<<"$files"
  return 0
}

# ---------- Consensus ----------

write_consensus() {
  local repo="$1" num="$2" sha="$3" hao="$4" dustin="$5"
  if [[ "$hao" == "$dustin" ]]; then
    post_pr_comment "$repo" "$num" "Consensus reached: $hao.

<!-- consensus: $sha verdict: $hao -->"
    log "    consensus=$hao"
  else
    post_pr_comment "$repo" "$num" "Reviewers disagree — escalating to human.

- Hao (Senior Engineer): $hao
- Dustin (Security & Performance Reviewer): $dustin

<!-- debate: $sha -->"
    log "    debate hao=$hao dustin=$dustin"
  fi
}

# ---------- Dispatch ----------

dispatch_agent() {
  local agent="$1"
  shift
  local items=("$@")
  [[ ${#items[@]} -eq 0 ]] && { log "[dispatch] $agent: empty queue"; return 0; }

  local pr_list
  pr_list=$(printf -- "- %s\n" "${items[@]}")
  local sentinel_name
  sentinel_name=$(printf '%s' "$agent" | tr '[:upper:]' '[:lower:]')

  local description
  description=$(cat <<EOF
Automated code review batch dispatched by \`pr-sweep.sh\` (every 15 min from \`stone16/agent-team\`).

For each pull request below, perform a code review per your agent skill (Code Review Verdict format) and post a review comment on the PR ending with your sentinel marker. The PR-sweep script reads the sentinel on the next run; without it your review will not register.

PRs to review (format: \`owner/repo#num@sha\` — the SHA shows the head when this batch was assembled):

$pr_list

Operational reminders:

1. Read each PR's CURRENT \`headRefOid\` immediately before posting your sentinel:
   \`\`\`
   gh pr view <num> --repo <owner/repo> --json headRefOid --jq .headRefOid
   \`\`\`
   Use that SHA in your sentinel — commits may have landed since this batch was assembled.

2. One review comment per PR. End it with the sentinel exactly:
   \`\`\`
   <!-- ${sentinel_name}-reviewed: <head-sha> verdict: <approve|request-changes|block> -->
   \`\`\`

3. Verdicts are exactly one of: \`approve\`, \`request-changes\`, \`block\`. The \`pr-sweep.sh\` parser is strict; other words are ignored.

4. When all PRs are reviewed, post a one-line summary comment on this Multica issue and set status to \`in_review\`. If a PR errors out (auth, rate limit, vanished), note it in the summary; the next sweep will retry.

5. Do not coordinate with the other reviewer in advance. Independent verdicts are the point — the script reconciles.
EOF
)

  log "[dispatch] $agent: ${#items[@]} PR(s)"
  printf '%s' "$description" | multica issue create \
    --title "PR review batch — ${#items[@]} PR(s)" \
    --assignee "$agent" \
    --priority low \
    --description-stdin \
    --output json >/dev/null
}

# ---------- Main ----------

declare -a HAO_QUEUE=()
declare -a DUSTIN_QUEUE=()

REPOS=$(list_repos)
log "[scan] enumerated $(echo "$REPOS" | wc -l | tr -d ' ') repos under $GH_OWNER/"

REPOS_OK=0
REPOS_ERRORED=0
PRS_TOTAL=0

while IFS= read -r repo; do
  [[ -z "$repo" ]] && continue
  if is_repo_ignored "$repo"; then
    log "[skip] $repo (in .pr-sweep-ignore)"
    continue
  fi

  # Capture stdout + stderr separately so PAT-scope errors don't kill the sweep.
  if ! prs_raw=$(list_open_prs "$repo" 2>&1); then
    log "[error] $repo: $prs_raw"
    REPOS_ERRORED=$((REPOS_ERRORED + 1))
    continue
  fi
  REPOS_OK=$((REPOS_OK + 1))

  if [[ -z "$prs_raw" ]]; then
    # Repo has zero open PRs. Don't spam the log per repo (we have many).
    continue
  fi

  log "[scan] $repo"
  while IFS=$'\t' read -r num sha author; do
    [[ -z "$num" ]] && continue
    PRS_TOTAL=$((PRS_TOTAL + 1))
    pr_id="$GH_OWNER/$repo#$num@$sha"

    # Skip self-authored PRs to avoid self-review loops.
    if [[ "$author" == "$HAO_AGENT" || "$author" == "$DUSTIN_AGENT" ]]; then
      log "  [skip] $pr_id author=$author (self-review)"
      continue
    fi

    body=$(pr_comments_body "$repo" "$num")

    if has_final_sentinel "$body" "$sha"; then
      log "  [done] $pr_id (consensus or debate already at this SHA)"
      continue
    fi

    if is_docs_only "$repo" "$num"; then
      post_pr_comment "$repo" "$num" "Docs-only PR — skipping code review.

<!-- consensus: $sha verdict: approve -->"
      log "  [docs] $pr_id → consensus:approve"
      continue
    fi

    hao_v=$(sentinel_verdict "$body" "hao-reviewed" "$sha")
    dustin_v=$(sentinel_verdict "$body" "dustin-reviewed" "$sha")

    if [[ -n "$hao_v" && -n "$dustin_v" ]]; then
      write_consensus "$repo" "$num" "$sha" "$hao_v" "$dustin_v"
    elif [[ -n "$hao_v" ]]; then
      DUSTIN_QUEUE+=("$pr_id")
      log "  [need-dustin] $pr_id (hao=$hao_v)"
    elif [[ -n "$dustin_v" ]]; then
      HAO_QUEUE+=("$pr_id")
      log "  [need-hao] $pr_id (dustin=$dustin_v)"
    else
      HAO_QUEUE+=("$pr_id")
      DUSTIN_QUEUE+=("$pr_id")
      log "  [need-both] $pr_id"
    fi
  done <<<"$prs_raw"
done <<<"$REPOS"

log "[summary] repos_ok=$REPOS_OK repos_errored=$REPOS_ERRORED prs_seen=$PRS_TOTAL"

# Bash 3 + set -u guards: don't deref empty arrays unsafely.
dispatch_agent "$HAO_AGENT" "${HAO_QUEUE[@]+"${HAO_QUEUE[@]}"}"
dispatch_agent "$DUSTIN_AGENT" "${DUSTIN_QUEUE[@]+"${DUSTIN_QUEUE[@]}"}"

log "[done] sweep complete: hao_queue=${#HAO_QUEUE[@]} dustin_queue=${#DUSTIN_QUEUE[@]}"
