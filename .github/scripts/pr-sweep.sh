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
CTO_AGENT="${CTO_AGENT:-Stometa}"

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
  # Don't let a single comment-write failure (e.g., PAT lacks write scope on
  # this repo, rate limit, vanished PR) abort the entire sweep. Log and move on.
  if ! printf '%s' "$body" | gh pr comment "$2" --repo "$GH_OWNER/$1" --body-file - 2>&1; then
    log "    [warn] post_pr_comment failed for $GH_OWNER/$1#$2 (continuing)"
    return 1
  fi
  return 0
}

pr_url() {
  printf 'https://github.com/%s/%s/pull/%s' "$GH_OWNER" "$1" "$2"
}

pr_markdown_link() {
  printf '[%s/%s#%s](%s)' "$GH_OWNER" "$1" "$2" "$(pr_url "$1" "$2")"
}

review_queue_item() {
  local repo="$1" num="$2" sha="$3"
  printf '%s @ %s' "$(pr_markdown_link "$repo" "$num")" "$sha"
}

# ---------- Sentinel parsing ----------

# Returns the verdict word if a sentinel matching <name>: <sha> verdict: <v>
# exists in the body, else empty.
sentinel_verdict() {
  local body="$1" name="$2" sha="$3"
  # Pipeline returns 1 when grep finds no sentinel — that's the common
  # case (most PRs have no review yet). The `|| true` keeps the function
  # returning 0 with empty stdout so callers using `var=$(...)` under
  # set -e -o pipefail don't blow up.
  printf '%s' "$body" \
    | grep -oE "${name}:[[:space:]]*${sha}[[:space:]]+verdict:[[:space:]]*[a-z-]+" \
    | tail -1 \
    | sed -E "s/.*verdict:[[:space:]]*([a-z-]+).*/\1/" \
    || true
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
      *.md|*.markdown|*.txt|*.rst|*.adoc|docs/*|*/docs/*) ;;
      *) return 1 ;;
    esac
  done <<<"$files"
  return 0
}

# ---------- Consensus ----------

write_consensus() {
  local repo="$1" num="$2" sha="$3" hao="$4" dustin="$5"

  if [[ "$hao" == "$dustin" ]]; then
    if post_pr_comment "$repo" "$num" "Consensus reached: $hao.

<!-- consensus: $sha verdict: $hao -->"; then
      log "    consensus=$hao"
      if [[ "$hao" != "approve" ]]; then
        dispatch_cto_delegation "$repo" "$num" "$sha" "consensus:$hao" "$hao" "$dustin"
      fi
    else
      log "    [warn] consensus comment not written for $GH_OWNER/$repo#$num; skipping CTO delegation until next sweep"
    fi
  else
    if post_pr_comment "$repo" "$num" "Reviewers disagree — escalating to human.

- Hao (Senior Engineer): $hao
- Dustin (Security & Performance Reviewer): $dustin

<!-- debate: $sha -->"; then
      log "    debate hao=$hao dustin=$dustin"
      dispatch_cto_delegation "$repo" "$num" "$sha" "debate" "$hao" "$dustin"
    else
      log "    [warn] debate comment not written for $GH_OWNER/$repo#$num; skipping CTO delegation until next sweep"
    fi
  fi
}

dispatch_cto_delegation() {
  local repo="$1" num="$2" sha="$3" outcome="$4" hao="$5" dustin="$6"
  local link
  link="$(pr_markdown_link "$repo" "$num")"

  local description
  description=$(cat <<EOF
CTO delegation needed for $link.

- PR: $link
- Head commit: $sha
- Review outcome: $outcome
- Reviewer verdicts: Hao=$hao, Dustin=$dustin

Review the PR comments, decide whether the findings are correct, then delegate fixes to the right engineer. If the review is wrong, leave the correction on the PR and close this issue.

This issue is assigned to the CTO instead of relying on reviewer-written agent mentions. Manual agent mentions are easy to miss and can create loops; assignment gives one deterministic notification point after review action items exist.
EOF
)

  log "    cto-delegation=$CTO_AGENT $GH_OWNER/$repo#$num"
  if ! printf '%s' "$description" | multica issue create \
    --title "PR review delegation needed — $GH_OWNER/$repo#$num" \
    --assignee "$CTO_AGENT" \
    --priority high \
    --description-stdin \
    --output json >/dev/null; then
    log "    [warn] dispatch_cto_delegation failed for $GH_OWNER/$repo#$num (continuing)"
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

PRs to review (format: clickable \`owner/repo#num\` plus \`@\` head SHA — the SHA shows the head when this batch was assembled):

$pr_list

Both reviewers are required on every non-docs production-code PR; this is not a rotation. Hao owns general code-quality review. Dustin owns security, performance, and adversarial-input review. The lenses differ, but the review depth does not.

Minimum review bar is identical for both reviewers:

- Read the PR diff, linked issue, and changed files in surrounding context before posting.
- Cite \`file:line\` for every finding.
- Prioritize production-impacting defects over style, naming, or speculative architecture.
- Re-run the relevant verification when practical; otherwise state the exact verification gap.
- Use exactly one of \`approve\`, \`request-changes\`, or \`block\`.
- Do not write the sentinel unless you completed a real review of the current head SHA.

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

4. Use the PR link above in your PR comment and in this Multica issue summary. The PR number must remain visible as \`owner/repo#num\`; the URL must be clickable for revisit/check-in.

5. When all PRs are reviewed, post a one-line summary comment on this Multica issue and set status to \`in_review\`. If a PR errors out (auth, rate limit, vanished), note it in the summary; the next sweep will retry.

6. If you produce action items (\`request-changes\` or \`block\`), do not @-mention another agent yourself. The sweep creates a CTO-assigned delegation issue after both independent reviews are reconciled.

7. Do not coordinate with the other reviewer in advance. Independent verdicts are the point — the script reconciles.
EOF
)

  log "[dispatch] $agent: ${#items[@]} PR(s)"
  if ! printf '%s' "$description" | multica issue create \
    --title "PR review batch — ${#items[@]} PR(s)" \
    --assignee "$agent" \
    --priority low \
    --description-stdin \
    --output json >/dev/null; then
    log "    [warn] dispatch_agent failed for $agent (continuing)"
  fi
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
    pr_item="$(review_queue_item "$repo" "$num" "$sha")"

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
      if post_pr_comment "$repo" "$num" "Docs-only PR — skipping code review.

<!-- consensus: $sha verdict: approve -->"; then
        log "  [docs] $pr_id → consensus:approve"
      else
        log "  [warn] docs-only consensus comment not written for $pr_id; next sweep will retry"
      fi
      continue
    fi

    hao_v=$(sentinel_verdict "$body" "hao-reviewed" "$sha")
    dustin_v=$(sentinel_verdict "$body" "dustin-reviewed" "$sha")

    if [[ -n "$hao_v" && -n "$dustin_v" ]]; then
      write_consensus "$repo" "$num" "$sha" "$hao_v" "$dustin_v"
    elif [[ -n "$hao_v" ]]; then
      DUSTIN_QUEUE+=("$pr_item")
      log "  [need-dustin] $pr_id (hao=$hao_v)"
    elif [[ -n "$dustin_v" ]]; then
      HAO_QUEUE+=("$pr_item")
      log "  [need-hao] $pr_id (dustin=$dustin_v)"
    else
      HAO_QUEUE+=("$pr_item")
      DUSTIN_QUEUE+=("$pr_item")
      log "  [need-both] $pr_id"
    fi
  done <<<"$prs_raw"
done <<<"$REPOS"

log "[summary] repos_ok=$REPOS_OK repos_errored=$REPOS_ERRORED prs_seen=$PRS_TOTAL"

# Bash 3 + set -u guards: don't deref empty arrays unsafely.
dispatch_agent "$HAO_AGENT" "${HAO_QUEUE[@]+"${HAO_QUEUE[@]}"}"
dispatch_agent "$DUSTIN_AGENT" "${DUSTIN_QUEUE[@]+"${DUSTIN_QUEUE[@]}"}"

log "[done] sweep complete: hao_queue=${#HAO_QUEUE[@]} dustin_queue=${#DUSTIN_QUEUE[@]}"
