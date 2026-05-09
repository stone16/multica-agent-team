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
#        - only one reviewed → request the other reviewer in the PR's issue
#        - neither reviewed → request Hao first in the PR's issue
#   4. Create/reuse one Multica issue per PR, keyed by a hidden PR comment
#   5. If review reconciliation is actionable, notify CTO in that PR issue
#
# No LLM is invoked here. Hao / Dustin only run when review work exists.

set -euo pipefail

GH_OWNER="${GH_OWNER:-stone16}"
HAO_AGENT="${HAO_AGENT:-Hao}"
DUSTIN_AGENT="${DUSTIN_AGENT:-Dustin}"
CTO_AGENT="${CTO_AGENT:-Stometa}"
CTO_MENTION="${CTO_MENTION:-[@CTO](mention://agent/2669622c-24fd-4254-bab7-2a7c2a5c5e12)}"

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

# ---------- PR review issue dispatch ----------

review_outcome_marker() {
  local sha="$1"
  printf '<!-- multica-review-dispatched: %s -->' "$sha"
}

agent_slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

review_issue_marker() {
  local issue_id="$1"
  printf '<!-- multica-pr-review-issue: %s -->' "$issue_id"
}

review_issue_id_from_comments() {
  local comments="$1"
  printf '%s\n' "$comments" \
    | sed -nE 's/.*<!--[[:space:]]*multica-pr-review-issue:[[:space:]]*([^[:space:]<>]+)[[:space:]]*-->.*/\1/p' \
    | tail -1
}

review_request_marker() {
  local sha="$1" agent="$2"
  printf '<!-- multica-review-requested: %s agent: %s -->' "$sha" "$(agent_slug "$agent")"
}

json_id() {
  sed -nE 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1
}

issue_comment_has_marker() {
  local issue_id="$1" marker="$2" log_key="$3" repo="$4" num="$5" sha="$6"
  local comments

  if ! comments=$(multica issue comment list "$issue_id" --limit 100 --output json 2>/dev/null); then
    log "    [warn] issue_comment_has_marker failed for $issue_id; will try posting"
    return 1
  fi

  if printf '%s' "$comments" | grep -Fq "$marker"; then
    log "    $log_key=exists $issue_id $GH_OWNER/$repo#$num@$sha"
    return 0
  fi
  return 1
}

review_issue_description() {
  local repo="$1" num="$2" sha="$3"
  local pr_list
  pr_list=$(printf -- "- %s\n" "$(review_queue_item "$repo" "$num" "$sha")")

  cat <<EOF
This is the single Multica thread for this PR review.

PR: $(review_queue_item "$repo" "$num" "$sha")
Idempotency key: $(pr_url "$repo" "$num")

The sweep reuses this issue for every head SHA on this PR. New pushes append a new review request comment; older review comments are stale when their SHA differs. The issue is marked \`done\` when both reviewers approve. If either reviewer requests changes, blocks, or disagrees, the sweep keeps this issue open and routes follow-up to CTO here.

PRs to review (format: clickable \`owner/repo#num\` plus \`@\` head SHA - the SHA shows the head when this request was assembled):

$pr_list

Both reviewers are required on every PR; this is not a rotation. Hao owns general code-quality review. Dustin owns security, performance, and adversarial-input review. The lenses differ, but the review depth does not. Documentation-only PRs receive the same dual review - for those, additionally verify that any code, CLI, or API claims in the docs match the current code, and watch for leaked secrets or internal URLs.

Minimum review bar is identical for both reviewers:

- Check out the PR head SHA into an isolated Multica worktree before reading code (see step 2 below). Diff-only review is not sufficient; cross-file references, callers, and adjacent-file conventions only become visible against the full repo.
- Read the PR diff, linked issue when present, and changed files in their surrounding repo context.
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
   This SHA is the unit of review - the same value MUST be used for the worktree checkout, the code reading, and the sentinel. Treat it as immutable until the sentinel is posted. The \`@<sha>\` shown in the request above may already be stale (commits can land between request assembly and your review); always re-fetch here.

2. Check out the PR head into an isolated Multica worktree against the SHA from step 1. Use this exact command (no \`git clone\`, no other refs):
   \`\`\`
   multica repo checkout https://github.com/<owner>/<repo>.git --ref <head-sha>
   \`\`\`
   Read code from the worktree path printed by the command - that is the only place where surrounding context, callers, and adjacent files are reliably consistent with the diff.

3. Conduct the review against the worktree. Then, IMMEDIATELY BEFORE posting the sentinel, re-run the \`headRefOid\` check from step 1. If the SHA is unchanged, post your sentinel tagged with that SHA. If the SHA has changed, the review is stale: DO NOT post a sentinel for the old SHA, even with \`verdict: block\`. Discard the review and restart from step 1 against the new SHA - new checkout, new read, new findings - then post. A sentinel must always reflect a review actually conducted on the SHA it tags.

4. If \`multica repo checkout\` fails because the SHA is unreachable (force-push, branch deleted, or the ref otherwise missing), DO NOT post a sentinel for that PR. Instead, post a plain note on this Multica issue summarizing which PR was unreachable and at which SHA; the next sweep will pick up the new head. Writing a sentinel for an SHA you could not actually review pollutes the consensus parser.

5. One review comment per PR. End it with the sentinel exactly:
   \`\`\`
   <!-- <hao|dustin>-reviewed: <head-sha> verdict: <approve|request-changes|block> -->
   \`\`\`

6. Verdicts are exactly one of: \`approve\`, \`request-changes\`, \`block\`. The \`pr-sweep.sh\` parser is strict; other words are ignored.

7. Use the PR link above in your PR comment and in this Multica issue summary. The PR number must remain visible as \`owner/repo#num\`; the URL must be clickable for revisit/check-in.

8. When your assigned review is complete, post a one-line summary comment on this Multica issue and set status to \`in_review\`. If a PR errors out (auth, rate limit, vanished), note it in the summary; the next sweep will retry.

9. If you produce action items (\`request-changes\` or \`block\`), do not @-mention another agent yourself. The sweep posts the reconciled outcome in this same issue after both reviews are reconciled.

10. Do not coordinate with the other reviewer in advance. The script reconciles the two verdicts.
EOF
}

create_review_issue() {
  local repo="$1" num="$2" sha="$3" assignee="$4"
  local created issue_id

  if ! created=$(review_issue_description "$repo" "$num" "$sha" | multica issue create \
    --title "PR review - $GH_OWNER/$repo#$num" \
    --assignee "$assignee" \
    --priority low \
    --description-stdin \
    --output json); then
    return 1
  fi

  issue_id="$(printf '%s' "$created" | json_id)"
  [[ -n "$issue_id" ]] || return 1

  if ! post_pr_comment "$repo" "$num" "$(review_issue_marker "$issue_id")" >/dev/null; then
    log "    [warn] review issue marker was not written for $GH_OWNER/$repo#$num; duplicate prevention may retry"
  fi

  printf '%s\n' "$issue_id"
}

ensure_review_issue() {
  local repo="$1" num="$2" sha="$3" comments="$4" assignee="$5"
  local issue_id

  issue_id="$(review_issue_id_from_comments "$comments")"
  if [[ -n "$issue_id" ]]; then
    printf '%s\n' "$issue_id"
    return 0
  fi

  create_review_issue "$repo" "$num" "$sha" "$assignee"
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

post_review_outcome_comment() {
  local issue_id="$1" repo="$2" num="$3" sha="$4" outcome="$5" hao="$6" dustin="$7"
  local action_kind="$8"
  local link marker hao_body dustin_body comment header
  link="$(pr_url "$repo" "$num")"
  marker="$(review_outcome_marker "$sha")"
  hao_body="$(review_comment_body "$repo" "$num" "hao-reviewed" "$sha")"
  dustin_body="$(review_comment_body "$repo" "$num" "dustin-reviewed" "$sha")"

  case "$action_kind" in
    cto-followup)
      header="$CTO_MENTION PR review came back with \`$outcome\`. Please handle the follow-up in this issue by deciding whether to fix, hand off, close, or override."
      ;;
    cto-debate)
      header="$CTO_MENTION Reviewers disagree on this PR. Please cast the deciding vote (approve / request-changes / block) in this issue so the loop can converge."
      ;;
    *)
      log "    [warn] unknown action_kind=$action_kind, defaulting to CTO escalation"
      header="$CTO_MENTION PR review needs routing."
      ;;
  esac

  comment=$(cat <<EOF
$header

- PR: $link
- Head commit: $sha
- Final verdict: $outcome
- Hao verdict: $hao
- Dustin verdict: $dustin
- Action: $action_kind

## Discussion Protocol

Reply to each reviewer finding in this issue with one of: \`will-fix\`, \`already-fixed\`, \`wont-fix\`, or \`needs-discussion\`.
State whether the finding is correct, what will change, or why it should not change.
Keep the thread unresolved until CTO and reviewer agree on the outcome.
End with a summary comment before marking the thread resolved.

## Hao Review

$hao_body

## Dustin Review

$dustin_body

$marker
EOF
)

  log "    review-outcome=post $issue_id $GH_OWNER/$repo#$num@$sha action=$action_kind"
  if ! printf '%s' "$comment" | multica issue comment add "$issue_id" --content-stdin >/dev/null; then
    log "    [warn] post_review_outcome_comment failed for $GH_OWNER/$repo#$num (continuing)"
    return 1
  fi
  return 0
}

dispatch_review_request() {
  local repo="$1" num="$2" sha="$3" comments="$4" agent="$5"
  local issue_id marker slug comment
  slug="$(agent_slug "$agent")"
  marker="$(review_request_marker "$sha" "$agent")"

  if ! issue_id="$(ensure_review_issue "$repo" "$num" "$sha" "$comments" "$agent")"; then
    log "    [warn] ensure_review_issue failed for $GH_OWNER/$repo#$num"
    return 1
  fi

  if ! multica issue update "$issue_id" --status in_progress --assignee "$agent" >/dev/null 2>&1; then
    log "    [warn] review issue update failed for $issue_id (continuing)"
  fi

  if issue_comment_has_marker "$issue_id" "$marker" "review-request" "$repo" "$num" "$sha"; then
    return 0
  fi

  comment=$(cat <<EOF
$agent review is requested for $(review_queue_item "$repo" "$num" "$sha").

Follow the instructions in this issue description. Post exactly one PR review comment ending with:

\`\`\`
<!-- ${slug}-reviewed: <head-sha> verdict: <approve|request-changes|block> -->
\`\`\`

After posting the PR review, add a one-line summary here and set this issue to \`in_review\`. Do not @-mention another agent; the sweep will move this same issue to the next reviewer or CTO.

$marker
EOF
)

  log "    review-request=post $issue_id $GH_OWNER/$repo#$num@$sha agent=$slug"
  if ! printf '%s' "$comment" | multica issue comment add "$issue_id" --content-stdin >/dev/null; then
    log "    [warn] dispatch_review_request failed for $agent on $GH_OWNER/$repo#$num (continuing)"
    return 1
  fi
  return 0
}

dispatch_review_outcome() {
  local repo="$1" num="$2" sha="$3" outcome="$4" hao="$5" dustin="$6" action_kind="$7" comments="$8"
  local issue_id marker
  marker="$(review_outcome_marker "$sha")"

  if ! issue_id="$(ensure_review_issue "$repo" "$num" "$sha" "$comments" "$CTO_AGENT")"; then
    log "    [warn] ensure_review_issue failed for $GH_OWNER/$repo#$num"
    return 1
  fi

  if issue_comment_has_marker "$issue_id" "$marker" "review-outcome" "$repo" "$num" "$sha"; then
    return 0
  fi

  if ! post_review_outcome_comment "$issue_id" "$repo" "$num" "$sha" "$outcome" "$hao" "$dustin" "$action_kind"; then
    return 1
  fi

  if ! multica issue update "$issue_id" --status in_progress --assignee "$CTO_AGENT" >/dev/null 2>&1; then
    log "    [warn] review issue update failed for $issue_id (continuing)"
  fi
  return 0
}

close_review_issue_if_known() {
  local repo="$1" num="$2" sha="$3" comments="$4"
  local issue_id
  issue_id="$(review_issue_id_from_comments "$comments")"
  [[ -n "$issue_id" ]] || return 0

  if multica issue update "$issue_id" --status done >/dev/null 2>&1; then
    log "    review-issue=done $issue_id $GH_OWNER/$repo#$num@$sha"
  else
    log "    [warn] review issue close failed for $issue_id (continuing)"
  fi
}

# ---------- Consensus ----------

write_consensus() {
  local repo="$1" num="$2" sha="$3" hao="$4" dustin="$5" comments="${6:-}"
  [[ -n "$comments" ]] || comments="$(pr_comments_body "$repo" "$num")"

  if [[ "$hao" == "$dustin" ]]; then
    if [[ "$hao" == "approve" ]]; then
      close_review_issue_if_known "$repo" "$num" "$sha" "$comments"
    elif ! dispatch_review_outcome "$repo" "$num" "$sha" "consensus: $hao" "$hao" "$dustin" "cto-followup" "$comments"; then
      log "    [warn] review issue dispatch not ready for $GH_OWNER/$repo#$num; skipping final sentinel until next sweep"
      return 0
    fi

    if post_pr_comment "$repo" "$num" "Consensus reached: $hao.

<!-- consensus: $sha verdict: $hao -->"; then
      log "    consensus=$hao"
    else
      log "    [warn] consensus comment not written for $GH_OWNER/$repo#$num; next sweep will retry final sentinel"
    fi
  else
    if ! dispatch_review_outcome "$repo" "$num" "$sha" "debate" "$hao" "$dustin" "cto-debate" "$comments"; then
      log "    [warn] review issue dispatch not ready for $GH_OWNER/$repo#$num; skipping final sentinel until next sweep"
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

# ---------- Main ----------

REPOS=$(list_repos)
log "[scan] enumerated $(echo "$REPOS" | wc -l | tr -d ' ') repos under $GH_OWNER/"

REPOS_OK=0
REPOS_ERRORED=0
PRS_TOTAL=0
REVIEWS_REQUESTED=0

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

    hao_v=$(sentinel_verdict "$body" "hao-reviewed" "$sha")
    dustin_v=$(sentinel_verdict "$body" "dustin-reviewed" "$sha")

    if [[ -n "$hao_v" && -n "$dustin_v" ]]; then
      write_consensus "$repo" "$num" "$sha" "$hao_v" "$dustin_v" "$body"
    elif [[ -n "$hao_v" ]]; then
      log "  [need-dustin] $pr_id (hao=$hao_v)"
      dispatch_review_request "$repo" "$num" "$sha" "$body" "$DUSTIN_AGENT" && REVIEWS_REQUESTED=$((REVIEWS_REQUESTED + 1))
    elif [[ -n "$dustin_v" ]]; then
      log "  [need-hao] $pr_id (dustin=$dustin_v)"
      dispatch_review_request "$repo" "$num" "$sha" "$body" "$HAO_AGENT" && REVIEWS_REQUESTED=$((REVIEWS_REQUESTED + 1))
    else
      log "  [need-hao-first] $pr_id"
      dispatch_review_request "$repo" "$num" "$sha" "$body" "$HAO_AGENT" && REVIEWS_REQUESTED=$((REVIEWS_REQUESTED + 1))
    fi
  done <<<"$prs_raw"
done <<<"$REPOS"

log "[summary] repos_ok=$REPOS_OK repos_errored=$REPOS_ERRORED prs_seen=$PRS_TOTAL"
log "[done] sweep complete: review_requests=$REVIEWS_REQUESTED"
