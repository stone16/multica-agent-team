#!/usr/bin/env bash
# pr-sweep.sh — deterministic filter that dispatches code-review work to
# Hao (Senior Engineer) and Dustin (Security & Performance Reviewer).
#
# Pipeline:
#   1. Enumerate open PRs across all non-archived stone16/* repos
#   2. For each PR, read sentinel state from PR comments
#   3. Decide what's needed:
#        - converged (consensus / debate sentinel for current SHA) → skip
#        - both reviewed at this SHA → compute consensus and write sentinel
#        - only one reviewed → enqueue the other
#        - neither reviewed → enqueue both
#   4. If queues non-empty, create one Multica issue per agent with the PR list
#   5. If review reconciliation is actionable, notify the originating issue
#
# No LLM is invoked here. Hao / Dustin only run when the queues actually have work.

set -euo pipefail

GH_OWNER="${GH_OWNER:-stone16}"
HAO_AGENT="${HAO_AGENT:-Hao}"
DUSTIN_AGENT="${DUSTIN_AGENT:-Dustin}"
CTO_AGENT="${CTO_AGENT:-Stometa}"
CTO_MENTION="${CTO_MENTION:-[@CTO](mention://agent/2669622c-24fd-4254-bab7-2a7c2a5c5e12)}"

# Max number of request-changes / block consensus rounds before the loop
# stops auto-routing back to the original author and escalates to CTO_MENTION.
# Each round = one distinct head SHA that landed a non-approve consensus.
# A 4th non-approve round on a 4th distinct SHA escalates instead of pinging
# the author again. Debate consensus always escalates regardless of count.
MAX_REVIEW_ITERATIONS="${MAX_REVIEW_ITERATIONS:-3}"

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

pr_body() {
  gh pr view "$2" --repo "$GH_OWNER/$1" --json body \
    --jq '.body // ""' 2>/dev/null || true
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

# ---------- Origin issue dispatch ----------

origin_issue_id_from_body() {
  local body="$1"
  printf '%s\n' "$body" \
    | sed -nE 's/.*mention:\/\/issue\/([0-9a-fA-F-]{36}).*/\1/p' \
    | head -1
}

# Extract the author agent UUID from the PR body's "Original author" line.
# Returns empty if the line is missing — caller falls back to escalating to CTO.
original_author_id_from_body() {
  local body="$1"
  printf '%s\n' "$body" \
    | sed -nE 's/.*mention:\/\/agent\/([0-9a-fA-F-]{36}).*/\1/p' \
    | head -1
}

# Render an `[@Agent](mention://agent/<uuid>)` link given the UUID.
# We don't have the agent's display name from this side, so use a generic label;
# Multica renders the link using the canonical name regardless.
author_mention() {
  local uuid="$1"
  printf '[@author](mention://agent/%s)' "$uuid"
}

# Count distinct prior head SHAs that landed a non-approve consensus on this PR.
# Used to decide whether to keep auto-iterating with the author or escalate.
# Reads PR comments (stateless across sweep runs by design — sentinels persist
# in the PR thread, so the counter survives without any external state store).
iteration_count() {
  local body="$1"
  printf '%s' "$body" \
    | grep -oE 'consensus:[[:space:]]*[a-f0-9]+[[:space:]]+verdict:[[:space:]]*(request-changes|block)' \
    | awk '{print $2}' \
    | sort -u \
    | grep -c . \
    || true
}

missing_origin_marker() {
  local sha="$1"
  printf '<!-- multica-origin-missing: %s -->' "$sha"
}

origin_dispatch_marker() {
  local sha="$1"
  printf '<!-- multica-review-dispatched: %s -->' "$sha"
}

post_missing_origin_warning() {
  local repo="$1" num="$2" sha="$3"
  local marker
  marker="$(missing_origin_marker "$sha")"
  local comments
  comments="$(pr_comments_body "$repo" "$num")"

  if printf '%s' "$comments" | grep -Fq "$marker"; then
    log "    origin-link=missing-warning-exists $GH_OWNER/$repo#$num@$sha"
    return 1
  fi

  post_pr_comment "$repo" "$num" "Originating Multica issue link is missing.

Add this near the top of the PR body:

\`Originating Multica issue: [STO-42](mention://issue/<uuid>)\`

The PR sweep will retry Multica dispatch on the next run after the body is fixed.

$marker" >/dev/null || true
  return 1
}

origin_issue_comment_exists() {
  local issue_id="$1" repo="$2" num="$3" sha="$4"
  local marker comments
  marker="$(origin_dispatch_marker "$sha")"

  if ! comments=$(multica issue comment list "$issue_id" --limit 100 --output json 2>/dev/null); then
    log "    [warn] origin_issue_comment_exists failed; will try posting origin comment"
    return 1
  fi

  if printf '%s' "$comments" | grep -Fq "$marker"; then
    log "    origin-comment=exists $issue_id $GH_OWNER/$repo#$num@$sha"
    return 0
  fi
  return 1
}

strip_review_sentinel() {
  local name="$1" sha="$2"
  sed -E "/<!--[[:space:]]*${name}:[[:space:]]*${sha}[[:space:]]+verdict:[[:space:]]*[a-z-]+[[:space:]]*-->/d"
}

review_comment_body() {
  local repo="$1" num="$2" name="$3" sha="$4"
  local jq_filter
  jq_filter="[.comments[] | select(.body | contains(\"${name}: ${sha}\")) | .body][-1] // \"\""

  gh pr view "$num" --repo "$GH_OWNER/$repo" --json comments --jq "$jq_filter" 2>/dev/null \
    | strip_review_sentinel "$name" "$sha" \
    || true
}

post_origin_issue_comment() {
  local issue_id="$1" repo="$2" num="$3" sha="$4" outcome="$5" hao="$6" dustin="$7"
  local recipient="$8" action_kind="$9" iter="${10:-0}"
  local link marker hao_body dustin_body comment header iter_line
  link="$(pr_url "$repo" "$num")"
  marker="$(origin_dispatch_marker "$sha")"
  hao_body="$(review_comment_body "$repo" "$num" "hao-reviewed" "$sha")"
  dustin_body="$(review_comment_body "$repo" "$num" "dustin-reviewed" "$sha")"

  case "$action_kind" in
    author-iteration)
      header="$recipient PR review came back with \`request-changes\`. Please address the items below by pushing a new commit to the PR. The next sweep tick will pick up the new SHA and re-review automatically."
      iter_line="- Iteration: $((iter + 1)) of $MAX_REVIEW_ITERATIONS (after this round, the next \`request-changes\` consensus will escalate to a human)"
      ;;
    max-iterations-escalation)
      header="$CTO_MENTION PR review loop hit the iteration cap ($MAX_REVIEW_ITERATIONS rounds of \`request-changes\` / \`block\` consensus). Auto-routing has stopped — please decide whether to land, close, hand off to a different author, or override the cap."
      iter_line="- Iteration count: $iter (cap: $MAX_REVIEW_ITERATIONS — reached)"
      ;;
    missing-author-escalation)
      header="$CTO_MENTION PR review came back with \`request-changes\`, but the PR body has no \`Original author: [@AgentName](mention://agent/<uuid>)\` line, so the loop cannot route the feedback back to an agent. Please decide who handles this PR."
      iter_line="- Iteration count: $iter (cap: $MAX_REVIEW_ITERATIONS)"
      ;;
    debate-escalation)
      header="$CTO_MENTION Reviewers disagree on this PR — the consensus is split. Please cast the deciding vote (approve / request-changes / block) so the loop can converge."
      iter_line=""
      ;;
    *)
      log "    [warn] unknown action_kind=$action_kind, defaulting to CTO escalation"
      header="$CTO_MENTION PR review needs routing."
      iter_line=""
      ;;
  esac

  local body_iter=""
  [[ -n "$iter_line" ]] && body_iter=$'\n'"$iter_line"

  comment=$(cat <<EOF
$header

- PR: $link
- Head commit: $sha
- Final verdict: $outcome
- Hao verdict: $hao
- Dustin verdict: $dustin$body_iter
- Action: $action_kind

## Hao Review

$hao_body

## Dustin Review

$dustin_body

$marker
EOF
)

  log "    origin-comment=post $issue_id $GH_OWNER/$repo#$num@$sha action=$action_kind iter=$iter"
  if ! printf '%s' "$comment" | multica issue comment add "$issue_id" --content-stdin >/dev/null; then
    log "    [warn] post_origin_issue_comment failed for $GH_OWNER/$repo#$num (continuing)"
    return 1
  fi
  return 0
}

# Decide how to route a finalized review back to the originating Multica issue.
# Routing matrix (consensus_kind = "consensus-non-approve" | "debate"):
#   debate                       → escalate to CTO_MENTION (humans break ties)
#   non-approve, missing author  → escalate to CTO_MENTION (no agent to ping)
#   non-approve, iter >= cap     → escalate to CTO_MENTION (cap reached)
#   non-approve, iter <  cap     → ping original author for another iteration
dispatch_origin_issue_comment() {
  local repo="$1" num="$2" sha="$3" outcome="$4" hao="$5" dustin="$6" consensus_kind="$7"
  local issue_id author_id pr_body_str pr_comments_str iter recipient action_kind
  pr_body_str="$(pr_body "$repo" "$num")"
  issue_id="$(origin_issue_id_from_body "$pr_body_str")"

  if [[ -z "$issue_id" ]]; then
    post_missing_origin_warning "$repo" "$num" "$sha"
    return 1
  fi

  if [[ "$consensus_kind" == "debate" ]]; then
    recipient="$CTO_MENTION"
    action_kind="debate-escalation"
    iter=0
  else
    pr_comments_str="$(pr_comments_body "$repo" "$num")"
    iter="$(iteration_count "$pr_comments_str")"
    : "${iter:=0}"
    author_id="$(original_author_id_from_body "$pr_body_str")"

    if [[ -z "$author_id" ]]; then
      recipient="$CTO_MENTION"
      action_kind="missing-author-escalation"
    elif (( iter >= MAX_REVIEW_ITERATIONS )); then
      recipient="$CTO_MENTION"
      action_kind="max-iterations-escalation"
    else
      recipient="$(author_mention "$author_id")"
      action_kind="author-iteration"
    fi
  fi

  origin_issue_comment_exists "$issue_id" "$repo" "$num" "$sha" \
    || post_origin_issue_comment "$issue_id" "$repo" "$num" "$sha" "$outcome" "$hao" "$dustin" "$recipient" "$action_kind" "$iter"
}

# ---------- Consensus ----------

write_consensus() {
  local repo="$1" num="$2" sha="$3" hao="$4" dustin="$5"

  if [[ "$hao" == "$dustin" ]]; then
    if [[ "$hao" != "approve" ]] && ! dispatch_origin_issue_comment "$repo" "$num" "$sha" "consensus: $hao" "$hao" "$dustin" "consensus-non-approve"; then
      log "    [warn] origin issue dispatch not ready for $GH_OWNER/$repo#$num; skipping final sentinel until next sweep"
      return 0
    fi

    if post_pr_comment "$repo" "$num" "Consensus reached: $hao.

<!-- consensus: $sha verdict: $hao -->"; then
      log "    consensus=$hao"
    else
      log "    [warn] consensus comment not written for $GH_OWNER/$repo#$num; next sweep will retry final sentinel"
    fi
  else
    if ! dispatch_origin_issue_comment "$repo" "$num" "$sha" "debate" "$hao" "$dustin" "debate"; then
      log "    [warn] origin issue dispatch not ready for $GH_OWNER/$repo#$num; skipping final sentinel until next sweep"
      return 0
    fi

    if post_pr_comment "$repo" "$num" "Reviewers disagree — escalating to human.

- Hao (Senior Engineer): $hao
- Dustin (Security & Performance Reviewer): $dustin

<!-- debate: $sha -->"; then
      log "    debate hao=$hao dustin=$dustin"
    else
      log "    [warn] debate comment not written for $GH_OWNER/$repo#$num; next sweep will retry final sentinel"
    fi
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

Both reviewers are required on every PR; this is not a rotation. Hao owns general code-quality review. Dustin owns security, performance, and adversarial-input review. The lenses differ, but the review depth does not. Documentation-only PRs receive the same dual review — for those, additionally verify that any code, CLI, or API claims in the docs match the current code, and watch for leaked secrets or internal URLs.

Minimum review bar is identical for both reviewers:

- Check out the PR head SHA into an isolated Multica worktree before reading code (see step 2 below). Diff-only review is not sufficient; cross-file references, callers, and adjacent-file conventions only become visible against the full repo.
- Read the PR diff, linked issue, and changed files in their surrounding repo context.
- Cite \`file:line\` for every finding.
- Prioritize production-impacting defects over style, naming, or speculative architecture.
- Re-run the relevant verification when practical; otherwise state the exact verification gap.
- Use exactly one of \`approve\`, \`request-changes\`, or \`block\`.
- Do not write the sentinel unless you completed a real review of the current head SHA against the full repo.

Operational reminders:

1. Read the PR's CURRENT \`headRefOid\` immediately before starting the review:
   \`\`\`
   gh pr view <num> --repo <owner/repo> --json headRefOid --jq .headRefOid
   \`\`\`
   This SHA is the unit of review — the same value MUST be used for the worktree checkout, the code reading, and the sentinel. Treat it as immutable until the sentinel is posted. The \`@<sha>\` shown in the batch above may already be stale (commits can land between batch assembly and your review); always re-fetch here.

2. Check out the PR head into an isolated Multica worktree against the SHA from step 1. Use this exact command (no \`git clone\`, no other refs):
   \`\`\`
   multica repo checkout https://github.com/<owner>/<repo>.git --ref <head-sha>
   \`\`\`
   Read code from the worktree path printed by the command — that is the only place where surrounding context, callers, and adjacent files are reliably consistent with the diff.

3. Conduct the review against the worktree. Then, IMMEDIATELY BEFORE posting the sentinel, re-run the \`headRefOid\` check from step 1. If the SHA is unchanged, post your sentinel tagged with that SHA. If the SHA has changed, the review is stale: DO NOT post a sentinel for the old SHA, even with \`verdict: block\`. Discard the review and restart from step 1 against the new SHA — new checkout, new read, new findings — then post. A sentinel must always reflect a review actually conducted on the SHA it tags.

4. If \`multica repo checkout\` fails because the SHA is unreachable (force-push, branch deleted, or the ref otherwise missing), DO NOT post a sentinel for that PR. Instead, post a plain note on this Multica issue summarizing which PR was unreachable and at which SHA; the next sweep will pick up the new head. Writing a sentinel for an SHA you could not actually review pollutes the consensus parser.

5. One review comment per PR. End it with the sentinel exactly:
   \`\`\`
   <!-- ${sentinel_name}-reviewed: <head-sha> verdict: <approve|request-changes|block> -->
   \`\`\`

6. Verdicts are exactly one of: \`approve\`, \`request-changes\`, \`block\`. The \`pr-sweep.sh\` parser is strict; other words are ignored.

7. Use the PR link above in your PR comment and in this Multica issue summary. The PR number must remain visible as \`owner/repo#num\`; the URL must be clickable for revisit/check-in.

8. When all PRs are reviewed, post a one-line summary comment on this Multica issue and set status to \`in_review\`. If a PR errors out (auth, rate limit, vanished), note it in the summary; the next sweep will retry.

9. If you produce action items (\`request-changes\` or \`block\`), do not @-mention another agent yourself. The sweep posts the reconciled outcome back to the originating Multica issue after both independent reviews are reconciled.

10. Do not coordinate with the other reviewer in advance. Independent verdicts are the point — the script reconciles.
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
