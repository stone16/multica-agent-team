#!/usr/bin/env bash
# pr-sweep.sh — deterministic filter that dispatches code-review work to the
# two review lanes: the Engineer peer lane (the Engineer instance that did NOT
# author the PR) and the Evaluator adversarial lane (security, performance,
# dependency risk, adversarial inputs).
#
# Pipeline:
#   1. Enumerate open PRs across all non-archived stone16/* repos
#   2. For each PR, read sentinel state from PR comments
#   3. Decide what's needed:
#        - consensus sentinel at current SHA → converged, skip
#        - debate sentinel at current SHA:
#            - CEO resolution sentinel (`ceo-resolved`) at the SAME SHA →
#              write the final consensus sentinel with the resolved verdict
#              and finish (approve → mark the review issue done; non-approve →
#              the CEO already owns rework from the adjudication, so record
#              the sentinel and stop — no new outcome comment)
#            - no resolution yet → log waiting-for-CEO-adjudication and skip
#              (a debate is NOT permanent-final)
#        - both lanes reviewed at this SHA → compute consensus and write sentinel
#        - only one lane reviewed → request the other lane in the PR's issue
#        - neither reviewed → request the peer Engineer first in the PR's issue
#      Evaluator-authored PRs are special: the adversarial lane never
#      self-reviews, so BOTH lanes are carried by the two Engineer instances
#      (peer: Engineer-A, adversarial checklist: Engineer-B) and consensus
#      accepts two `engineer-reviewed` sentinels from two distinct review
#      comments as the two lanes.
#   4. Create/reuse one Multica issue per PR, keyed by a hidden PR comment
#   5. Route the reconciled outcome in that same issue: EVERY non-approve
#      outcome (agreed request-changes, agreed block, lane disagreement)
#      escalates to the CEO. The script never @-mentions PR authors — only
#      the CEO mentions members (leader-only routing). The rework iteration
#      count is included as ADVISORY text so the CEO can enforce the cap
#
# No LLM is invoked here. Review lanes only run when review work exists.

set -euo pipefail

GH_OWNER="${GH_OWNER:-stone16}"

# Assignee names as Multica knows them (`multica issue ... --assignee <name>`).
ENGINEER_A_AGENT="${ENGINEER_A_AGENT:-Engineer-A}"
ENGINEER_B_AGENT="${ENGINEER_B_AGENT:-Engineer-B}"
EVALUATOR_AGENT="${EVALUATOR_AGENT:-Evaluator}"
CEO_AGENT="${CEO_AGENT:-CEO}"

# Mention links in the `[@Name](mention://agent/<uuid>)` form. Operational
# values live in GitHub Actions variables — never commit agent UUIDs to this
# repo. CEO_MENTION is the only mention this script ever emits: all
# non-approve outcomes route to the CEO, who dispatches rework (leader-only
# routing per the constitution). The Engineer/Evaluator mentions map the
# `Original author:` UUID in a PR body to a roster identity; that mapping
# picks the peer lane only — the script never mentions authors.
CEO_MENTION="${CEO_MENTION:-@CEO}"
ENGINEER_A_MENTION="${ENGINEER_A_MENTION:-}"
ENGINEER_B_MENTION="${ENGINEER_B_MENTION:-}"
EVALUATOR_MENTION="${EVALUATOR_MENTION:-}"

# Advisory rework cap. The script does not route to authors; every non-approve
# outcome goes to the CEO. This value only feeds the advisory iteration line in
# the outcome comment ("rework iteration N of M for this PR") so the CEO can
# enforce the cap — past it, the CEO escalates to the human instead of
# dispatching rework. Each round = one distinct head SHA that landed a
# non-approve consensus.
MAX_REVIEW_ITERATIONS="${MAX_REVIEW_ITERATIONS:-3}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IGNORE_FILE="$REPO_ROOT/.pr-sweep-ignore"

# Newline-separated repo names to exclude from the sweep. In CI this comes from
# the GitHub Actions variable `vars.PR_SWEEP_IGNORE`, so private repo names
# never need to be committed. When unset or empty, the tracked
# .pr-sweep-ignore file is the fallback during the transition.
PR_SWEEP_IGNORE="${PR_SWEEP_IGNORE:-}"

log() { printf '%s\n' "$*" >&2; }

# ---------- Ignore list ----------

ignore_list() {
  if [[ -n "$PR_SWEEP_IGNORE" ]]; then
    printf '%s\n' "$PR_SWEEP_IGNORE"
  elif [[ -f "$IGNORE_FILE" ]]; then
    cat "$IGNORE_FILE"
  fi
}

is_repo_ignored() {
  local repo="$1"
  # One repo name per line; lines starting with # are comments. `tr` strips
  # blanks/tabs/CRs per line but keeps newlines so multi-entry lists match.
  ignore_list \
    | grep -vE '^[[:space:]]*(#|$)' \
    | tr -d ' \t\r' \
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

# Read-failure discipline: these fetch helpers distinguish FAILURE (gh/API
# error → nonzero exit status) from genuinely-empty data (empty stdout, exit
# 0). Callers MUST check the exit status with `if ! out=$(...)`. On any read
# failure for a PR, the caller logs a warning, increments PRS_FETCH_FAILED,
# and skips that PR for this sweep — state is re-derived from the PR thread
# next run, so skipping is safe by design. No decision (peer-lane pick, issue
# dispatch, consensus, final sentinel) may ever be made from error-empty data.
pr_comments_body() {
  gh pr view "$2" --repo "$GH_OWNER/$1" --json comments \
    --jq '.comments[].body' 2>/dev/null
}

pr_body() {
  gh pr view "$2" --repo "$GH_OWNER/$1" --json body \
    --jq '.body // ""' 2>/dev/null
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

# Returns the verdict word if a sentinel matching
# <!-- <name>: <sha> verdict: <v> --> exists in the body, else empty.
# The regex requires the literal HTML-comment delimiters `<!--` and `-->`
# (same hardening as iteration_count below) so that prose merely QUOTING a
# sentinel — e.g. a backticked `ceo-resolved: <sha> verdict: approve` in a
# discussion or postmortem comment — can never converge a debate or alter
# sweep behavior. Only actual sentinels posted as HTML comments count.
sentinel_verdict() {
  local body="$1" name="$2" sha="$3"
  # Pipeline returns 1 when grep finds no sentinel — that's the common
  # case (most PRs have no review yet). The `|| true` keeps the function
  # returning 0 with empty stdout so callers using `var=$(...)` under
  # set -e -o pipefail don't blow up.
  printf '%s' "$body" \
    | grep -oE "<!--[[:space:]]*${name}:[[:space:]]*${sha}[[:space:]]+verdict:[[:space:]]*[a-z-]+[[:space:]]*-->" \
    | tail -1 \
    | sed -E "s/.*verdict:[[:space:]]*([a-z-]+).*/\1/" \
    || true
}

# Only the consensus sentinel is terminal for a SHA.
# Requires the full delimited form emitted by write-time code
# (`<!-- consensus: <sha> verdict: <v> -->`) so quoted prose cannot match.
has_consensus_sentinel() {
  local body="$1" sha="$2"
  printf '%s' "$body" \
    | grep -qE "<!--[[:space:]]*consensus:[[:space:]]*${sha}[[:space:]]+verdict:[[:space:]]*[a-z-]+[[:space:]]*-->"
}

# The debate sentinel is NOT terminal: it means the lanes disagreed and the
# CEO owes an adjudication. The CEO closes the loop by posting the resolution
# sentinel on the PR after casting the deciding vote in the Multica issue:
#   <!-- ceo-resolved: <head-sha> verdict: <approve|request-changes|block> -->
# debate + ceo-resolved at the SAME SHA → the sweep writes the final consensus
# sentinel with the resolved verdict. debate without ceo-resolved → the sweep
# logs "waiting for CEO adjudication" and skips (never treats it as final).
# Requires the full delimited form (`<!-- debate: <sha> -->`) so quoted
# prose cannot match.
has_debate_sentinel() {
  local body="$1" sha="$2"
  printf '%s' "$body" \
    | grep -qE "<!--[[:space:]]*debate:[[:space:]]*${sha}[[:space:]]*-->"
}

# All verdicts for a lane sentinel at this SHA, one per line, in thread order.
# Used for Evaluator-authored PRs, where BOTH lanes write `engineer-reviewed`
# sentinels in two distinct review comments (first = peer, second =
# adversarial checklist). Requires the `<!-- -->` delimiters, same as
# sentinel_verdict, so quoted prose cannot inject verdicts.
sentinel_verdicts_all() {
  local body="$1" name="$2" sha="$3"
  printf '%s' "$body" \
    | grep -oE "<!--[[:space:]]*${name}:[[:space:]]*${sha}[[:space:]]+verdict:[[:space:]]*[a-z-]+[[:space:]]*-->" \
    | sed -E "s/.*verdict:[[:space:]]*([a-z-]+).*/\1/" \
    || true
}

# Count distinct prior head SHAs that landed a non-approve consensus on this PR.
# Feeds the ADVISORY iteration line in the CEO outcome comment; the CEO uses it
# to decide between dispatching rework and escalating to the human.
# Reads PR comments (stateless across sweep runs by design — sentinels persist
# in the PR thread, so the counter survives without any external state store).
#
# The regex requires the literal HTML-comment delimiters `<!--` and `-->` so
# that prose discussing prior verdicts (e.g. quoted sentinels in a postmortem
# comment, or an excerpt of an earlier sweep notification) does not inflate
# the counter and trigger a premature CEO escalation. Only actual sentinels
# emitted by `write_consensus()` count.
iteration_count() {
  local body="$1"
  printf '%s' "$body" \
    | grep -oE '<!--[[:space:]]*consensus:[[:space:]]*[a-f0-9]+[[:space:]]+verdict:[[:space:]]*(request-changes|block)[[:space:]]*-->' \
    | awk '{print $3}' \
    | sort -u \
    | grep -c . \
    || true
}

# ---------- Roster identity ----------

# Extract the agent UUID from a `[@Name](mention://agent/<uuid>)` link.
mention_agent_uuid() {
  printf '%s\n' "$1" \
    | sed -nE 's/.*mention:\/\/agent\/([0-9a-fA-F-]{36}).*/\1/p' \
    | head -1
}

# Extract the author agent UUID from the PR body's "Original author:" line.
# Anchored to a line beginning with "Original author:" (optional leading
# whitespace) so that an unrelated agent mention elsewhere in the body —
# a thank-you, a CC list, a quoted escalation — does not get treated as
# the author. Returns empty if the line is absent or carries no agent
# mention; callers fall back to the Engineer-A peer default, and the CEO
# outcome comment notes that the author could not be identified.
original_author_id_from_body() {
  local body="$1"
  # `|| true`: grep exits 1 when the line is absent (human-authored PRs);
  # keep the function at rc 0 with empty stdout so top-level `var=$(...)`
  # assignments under set -e -o pipefail don't abort the sweep.
  printf '%s\n' "$body" \
    | grep -E '^[[:space:]]*Original author:' \
    | sed -nE 's/.*mention:\/\/agent\/([0-9a-fA-F-]{36}).*/\1/p' \
    | head -1 \
    || true
}

# Extract the exact author mention markdown — `[@Name](mention://agent/<uuid>)`
# — from the PR body's "Original author:" line. It feeds the informational
# `- Original author:` line in the CEO outcome comment (wrapped in backticks
# there so it never acts as a live mention — leader-only routing holds).
# Returns empty when the line is absent or its mention markdown is unparseable.
original_author_mention_from_body() {
  local body="$1"
  printf '%s\n' "$body" \
    | grep -E '^[[:space:]]*Original author:' \
    | grep -oE '\[@[^]]+\]\(mention://agent/[0-9a-fA-F-]{36}\)' \
    | head -1 \
    || true
}

# Peer-lane pick: the Engineer instance that did not author the PR.
# Original author is Engineer-A → Engineer-B reviews. Engineer-B → Engineer-A.
# Anything else (Evaluator, PM, human, missing/unmapped author) → Engineer-A.
peer_engineer_for_author() {
  local author_uuid="$1" a_uuid
  a_uuid="$(mention_agent_uuid "$ENGINEER_A_MENTION")"
  if [[ -n "$author_uuid" && -n "$a_uuid" && "$author_uuid" == "$a_uuid" ]]; then
    printf '%s' "$ENGINEER_B_AGENT"
  else
    printf '%s' "$ENGINEER_A_AGENT"
  fi
}

# Sentinel lane for an agent: both Engineer instances write `engineer-reviewed`;
# the Evaluator writes `evaluator-reviewed`. The sentinel is lane-scoped, not
# instance-scoped, so a re-review by the other instance stays comparable.
review_lane_for_agent() {
  if [[ "$1" == "$EVALUATOR_AGENT" ]]; then
    printf 'evaluator'
  else
    printf 'engineer'
  fi
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

The sweep reuses this issue for every head SHA on this PR. New pushes append a new review request comment; older review comments are stale when their SHA differs. The issue is marked \`done\` when both lanes approve. Every non-approve outcome — agreed request-changes, agreed block, or lane disagreement — is escalated to the CEO in this issue; the sweep never @-mentions the PR's author. The CEO dispatches rework, honoring the advisory rework-iteration count in the outcome comment (once the count reaches the cap of $MAX_REVIEW_ITERATIONS, the CEO escalates to the human instead of dispatching — a further iteration is never authorized). A lane disagreement converges only after the CEO posts the \`ceo-resolved\` resolution sentinel on the PR.

PRs to review (format: clickable \`owner/repo#num\` plus \`@\` head SHA - the SHA shows the head when this request was assembled):

$pr_list

Two review lanes are required on every PR; this is not a rotation. The Engineer peer lane — the Engineer instance that did not author the PR — owns general code-quality review. The Evaluator adversarial lane owns security, performance, dependency-risk, and adversarial-input review. The lenses differ, but the review depth does not. Documentation-only PRs receive the same dual review - for those, additionally verify that any code, CLI, or API claims in the docs match the current code, and watch for leaked secrets or internal URLs.

Minimum review bar is identical for both lanes:

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

5. One review comment per PR. End it with the sentinel for your lane exactly:
   \`\`\`
   <!-- <engineer|evaluator>-reviewed: <head-sha> verdict: <approve|request-changes|block> -->
   \`\`\`
   Engineer instances (A or B) both use \`engineer-reviewed\`; the Evaluator uses \`evaluator-reviewed\`.

6. Verdicts are exactly one of: \`approve\`, \`request-changes\`, \`block\`. The \`pr-sweep.sh\` parser is strict; other words are ignored.

7. Use the PR link above in your PR comment and in this Multica issue summary. The PR number must remain visible as \`owner/repo#num\`; the URL must be clickable for revisit/check-in.

8. When your assigned review is complete, post a one-line summary comment on this Multica issue and set status to \`in_review\`. If a PR errors out (auth, rate limit, vanished), note it in the summary; the next sweep will retry.

9. If you produce action items (\`request-changes\` or \`block\`), do not @-mention another agent yourself. The sweep posts the reconciled outcome in this same issue after both lanes are reconciled.

10. Do not coordinate with the other lane in advance. The script reconciles the two verdicts.
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

# Fetch one lane's review comment body (sentinel stripped). `idx` selects
# which matching comment (-1 = last, -2 = second-to-last; the latter is used
# for the peer review on Evaluator-authored PRs where both lanes write
# `engineer-reviewed`). Returns nonzero on a FAILED fetch — callers must not
# treat a failure as an empty review body.
review_comment_body() {
  local repo="$1" num="$2" name="$3" sha="$4" idx="${5:--1}"
  local jq_filter raw
  jq_filter="[.comments[] | select(.body | contains(\"${name}: ${sha}\")) | .body][${idx}] // \"\""

  if ! raw=$(gh pr view "$num" --repo "$GH_OWNER/$repo" --json comments --jq "$jq_filter" 2>/dev/null); then
    return 1
  fi
  printf '%s' "$raw" | strip_review_sentinel "$name" "$sha"
}

post_review_outcome_comment() {
  local issue_id="$1" repo="$2" num="$3" sha="$4" outcome="$5" engineer="$6" evaluator="$7"
  local action_kind="$8" reason="$9" iter="${10}" author_mention="${11:-}" lane_mode="${12:-standard}"
  local link marker engineer_body evaluator_body comment header iter_line protocol author_line
  local peer_name="engineer-reviewed" adv_name="evaluator-reviewed" peer_idx="-1" adv_idx="-1"
  local peer_verdict_label="Engineer verdict (peer lane)"
  local adv_verdict_label="Evaluator verdict (adversarial lane)"
  local peer_section="Engineer Review (peer lane)"
  local adv_section="Evaluator Review (adversarial lane)"
  link="$(pr_url "$repo" "$num")"
  marker="$(review_outcome_marker "$sha")"

  if [[ "$lane_mode" == "engineer-pair" ]]; then
    # Evaluator-authored PR: both lanes wrote `engineer-reviewed` sentinels in
    # two distinct review comments — first is the peer lane, second is the
    # adversarial checklist lane.
    adv_name="engineer-reviewed"
    peer_idx="-2"
    peer_verdict_label="Peer lane verdict (Engineer)"
    adv_verdict_label="Adversarial lane verdict (Engineer — Evaluator-authored PR)"
    peer_section="Peer Lane Review (Engineer)"
    adv_section="Adversarial Lane Review (Engineer — Evaluator-authored PR)"
  fi

  # A failed review-body fetch must not degrade into an empty-findings outcome
  # comment: skip this PR for the sweep instead (state re-derives next run).
  if ! engineer_body="$(review_comment_body "$repo" "$num" "$peer_name" "$sha" "$peer_idx")"; then
    log "    [warn] fetch failed for peer review body on $GH_OWNER/$repo#$num; skipping this sweep"
    PRS_FETCH_FAILED=$((PRS_FETCH_FAILED + 1))
    return 1
  fi
  if ! evaluator_body="$(review_comment_body "$repo" "$num" "$adv_name" "$sha" "$adv_idx")"; then
    log "    [warn] fetch failed for adversarial review body on $GH_OWNER/$repo#$num; skipping this sweep"
    PRS_FETCH_FAILED=$((PRS_FETCH_FAILED + 1))
    return 1
  fi

  # Author identity for the CEO's rework dispatch. The mention markdown is
  # wrapped in backticks so this line stays informational — the sweep never
  # emits a live mention of the author (leader-only routing).
  if [[ -n "$author_mention" ]]; then
    author_line="- Original author: \`${author_mention}\` (backticked — informational, not a live mention; rework routing stays with the CEO)"
  else
    author_line="- Original author: unknown (human-authored or preamble unparseable) — no agent rework target; treat as human-owned"
  fi

  # Leader-only routing: every header below mentions ONLY the CEO. The script
  # never @-mentions PR authors; the CEO dispatches rework. The iteration line
  # is advisory — it lets the CEO enforce MAX_REVIEW_ITERATIONS.
  case "$action_kind" in
    ceo-followup)
      if [[ "$reason" == "missing-author" ]]; then
        header="$CEO_MENTION PR review came back with \`$outcome\`, and the PR body has no \`Original author: [@AgentName](mention://agent/<uuid>)\` line, so the author agent cannot be identified. Please handle the follow-up in this issue: identify an owner and dispatch rework with a DoD referencing the findings below, or hand off, close, or override."
      else
        header="$CEO_MENTION PR review came back with \`$outcome\`. Please dispatch rework to the PR's author agent (identity on the \`- Original author:\` line below) with a DoD referencing the findings below, or hand off, close, or override. The sweep does not route to authors; routing is yours."
      fi
      if (( iter >= MAX_REVIEW_ITERATIONS )); then
        iter_line="- Rework iterations so far: $iter (cap: $MAX_REVIEW_ITERATIONS — reached; advisory: escalate to the human instead of dispatching rework)"
      else
        iter_line="- Rework iteration $((iter + 1)) of $MAX_REVIEW_ITERATIONS for this PR (advisory — the CEO enforces the cap; past it, escalate to the human)"
      fi
      protocol=$(cat <<'PROTO'
## Discussion Protocol

Reply to each reviewer finding in this issue with one of: `will-fix`, `already-fixed`, `wont-fix`, or `needs-discussion`.
State whether the finding is correct, what will change, or why it should not change.
Keep the thread unresolved until the CEO and the reviewer agree on the outcome.
End with a summary comment before marking the thread resolved.
PROTO
)
      ;;
    ceo-debate)
      header="$CEO_MENTION Reviewers disagree on this PR. Please cast the deciding vote (approve / request-changes / block) in this issue, then post the resolution sentinel as a PR comment exactly as \`<!-- ceo-resolved: $sha verdict: <approve|request-changes|block> -->\` — that sentinel is what lets the sweep converge; without it the debate stays open."
      iter_line=""
      protocol=$(cat <<'PROTO'
## Discussion Protocol

Reply to each reviewer finding in this issue with one of: `will-fix`, `already-fixed`, `wont-fix`, or `needs-discussion`.
State whether the finding is correct, what will change, or why it should not change.
Keep the thread unresolved until the CEO and the reviewer agree on the outcome.
End with a summary comment before marking the thread resolved.
PROTO
)
      ;;
    *)
      log "    [warn] unknown action_kind=$action_kind, defaulting to CEO escalation"
      header="$CEO_MENTION PR review needs routing."
      iter_line=""
      protocol=""
      ;;
  esac

  local body_iter=""
  [[ -n "$iter_line" ]] && body_iter=$'\n'"$iter_line"

  comment=$(cat <<EOF
$header

- PR: $link
- Head commit: $sha
- Final verdict: $outcome
- $peer_verdict_label: $engineer
- $adv_verdict_label: $evaluator
$author_line$body_iter
- Action: $action_kind

$protocol

## $peer_section

$engineer_body

## $adv_section

$evaluator_body

$marker
EOF
)

  log "    review-outcome=post $issue_id $GH_OWNER/$repo#$num@$sha action=$action_kind iter=$iter"
  if ! printf '%s' "$comment" | multica issue comment add "$issue_id" --content-stdin >/dev/null; then
    log "    [warn] post_review_outcome_comment failed for $GH_OWNER/$repo#$num (continuing)"
    return 1
  fi
  return 0
}

dispatch_review_request() {
  local repo="$1" num="$2" sha="$3" comments="$4" agent="$5" lane_role="${6:-}"
  local issue_id marker lane lane_desc lane_note comment
  lane="$(review_lane_for_agent "$agent")"
  marker="$(review_request_marker "$sha" "$agent")"
  lane_note=""

  if [[ "$lane_role" == "adversarial-engineer" ]]; then
    # Evaluator-authored PR: the adversarial lane never self-reviews, so the
    # adversarial checklist is carried by an Engineer instance.
    lane="engineer"
    lane_desc="the adversarial lane on an Evaluator-authored PR: security, performance, dependency risk, and adversarial inputs. The Evaluator never reviews its own PR, so this lane is carried by an Engineer instance"
    lane_note="Lane attribution note: this PR was authored by the Evaluator, so BOTH lanes are carried by Engineer instances. Run the adversarial checklist, but write the \`engineer-reviewed\` sentinel (never \`evaluator-reviewed\`); the sweep accepts two \`engineer-reviewed\` sentinels from two distinct review comments as the two lanes (first = peer, second = adversarial)."
  elif [[ "$lane" == "evaluator" ]]; then
    lane_desc="the Evaluator adversarial lane: security, performance, dependency risk, and adversarial inputs"
  else
    lane_desc="the Engineer peer lane: general code quality, as the Engineer instance that did not author this PR"
  fi

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

  local note_block=""
  [[ -n "$lane_note" ]] && note_block=$'\n'"$lane_note"$'\n'

  comment=$(cat <<EOF
$agent review is requested for $(review_queue_item "$repo" "$num" "$sha").

You are reviewing $lane_desc. Follow the instructions in this issue description. Post exactly one PR review comment ending with:

\`\`\`
<!-- ${lane}-reviewed: <head-sha> verdict: <approve|request-changes|block> -->
\`\`\`
$note_block
After posting the PR review, add a one-line summary here and set this issue to \`in_review\`. Do not @-mention another agent; the sweep will move this same issue to the other lane or, on any non-approve outcome, to the CEO.

$marker
EOF
)

  log "    review-request=post $issue_id $GH_OWNER/$repo#$num@$sha agent=$(agent_slug "$agent") lane=$lane"
  if ! printf '%s' "$comment" | multica issue comment add "$issue_id" --content-stdin >/dev/null; then
    log "    [warn] dispatch_review_request failed for $agent on $GH_OWNER/$repo#$num (continuing)"
    return 1
  fi
  return 0
}

dispatch_review_outcome() {
  local repo="$1" num="$2" sha="$3" outcome="$4" engineer="$5" evaluator="$6"
  local action_kind="$7" reason="$8" iter="$9" comments="${10}" author_mention="${11:-}" lane_mode="${12:-standard}"
  local issue_id marker
  marker="$(review_outcome_marker "$sha")"
  # Every non-approve outcome is owned by the CEO — the script never assigns
  # or mentions the PR's author; the CEO dispatches rework from here.

  if ! issue_id="$(ensure_review_issue "$repo" "$num" "$sha" "$comments" "$CEO_AGENT")"; then
    log "    [warn] ensure_review_issue failed for $GH_OWNER/$repo#$num"
    return 1
  fi

  if issue_comment_has_marker "$issue_id" "$marker" "review-outcome" "$repo" "$num" "$sha"; then
    return 0
  fi

  if ! post_review_outcome_comment "$issue_id" "$repo" "$num" "$sha" "$outcome" "$engineer" "$evaluator" "$action_kind" "$reason" "$iter" "$author_mention" "$lane_mode"; then
    return 1
  fi

  if ! multica issue update "$issue_id" --status in_progress --assignee "$CEO_AGENT" >/dev/null 2>&1; then
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

# Routing matrix for a finalized review (leader-only routing — the script
# mentions ONLY the CEO; the CEO dispatches any rework):
#   lanes disagree        → ceo-debate (CEO casts the deciding vote)
#   non-approve consensus → ceo-followup (CEO dispatches rework; the advisory
#                           iteration line lets the CEO enforce the cap)
#   approve + approve     → close the PR's review issue
write_consensus() {
  local repo="$1" num="$2" sha="$3" engineer="$4" evaluator="$5" comments="${6:-}" author_uuid="${7:-}" author_mention="${8:-}" lane_mode="${9:-standard}"
  local peer_lane_label="Engineer (peer lane)" adv_lane_label="Evaluator (adversarial lane)"
  if [[ "$lane_mode" == "engineer-pair" ]]; then
    adv_lane_label="Engineer (adversarial lane — Evaluator-authored PR)"
  fi
  if [[ -z "$comments" ]]; then
    if ! comments="$(pr_comments_body "$repo" "$num")"; then
      log "    [warn] fetch failed for PR comments on $GH_OWNER/$repo#$num; skipping this sweep"
      PRS_FETCH_FAILED=$((PRS_FETCH_FAILED + 1))
      return 0
    fi
  fi

  if [[ "$engineer" == "$evaluator" ]]; then
    if [[ "$engineer" == "approve" ]]; then
      close_review_issue_if_known "$repo" "$num" "$sha" "$comments"
    else
      local iter reason
      iter="$(iteration_count "$comments")"
      : "${iter:=0}"

      reason=""
      [[ -z "$author_uuid" ]] && reason="missing-author"

      if ! dispatch_review_outcome "$repo" "$num" "$sha" "consensus: $engineer" "$engineer" "$evaluator" "ceo-followup" "$reason" "$iter" "$comments" "$author_mention" "$lane_mode"; then
        log "    [warn] review issue dispatch not ready for $GH_OWNER/$repo#$num; skipping final sentinel until next sweep"
        return 0
      fi
    fi

    if post_pr_comment "$repo" "$num" "Consensus reached: $engineer.

<!-- consensus: $sha verdict: $engineer -->"; then
      log "    consensus=$engineer"
    else
      log "    [warn] consensus comment not written for $GH_OWNER/$repo#$num; next sweep will retry final sentinel"
    fi
  else
    if ! dispatch_review_outcome "$repo" "$num" "$sha" "debate" "$engineer" "$evaluator" "ceo-debate" "" 0 "$comments" "$author_mention" "$lane_mode"; then
      log "    [warn] review issue dispatch not ready for $GH_OWNER/$repo#$num; skipping final sentinel until next sweep"
      return 0
    fi

    if post_pr_comment "$repo" "$num" "Reviewers disagree — escalating to the CEO for adjudication. The debate stays open until the CEO posts the resolution sentinel on this PR: \`<!-- ceo-resolved: $sha verdict: <approve|request-changes|block> -->\`.

- $peer_lane_label: $engineer
- $adv_lane_label: $evaluator

<!-- debate: $sha -->"; then
      log "    debate engineer=$engineer evaluator=$evaluator"
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
PRS_FETCH_FAILED=0
REVIEWS_REQUESTED=0

while IFS= read -r repo; do
  [[ -z "$repo" ]] && continue
  if is_repo_ignored "$repo"; then
    log "[skip] $repo (ignore list)"
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
  # NOTE: there is deliberately no GitHub-login self-review skip here. Agent
  # identity comes from the PR body's `Original author:` line (instances can
  # share a bot login); the peer-lane pick below structurally prevents an
  # Engineer instance from reviewing its own PR.
  while IFS=$'\t' read -r num sha _author; do
    [[ -z "$num" ]] && continue
    PRS_TOTAL=$((PRS_TOTAL + 1))
    pr_id="$GH_OWNER/$repo#$num@$sha"

    # A failed read is never treated as empty data — skip the PR for this
    # sweep instead (state re-derives from the PR thread next run).
    if ! body=$(pr_comments_body "$repo" "$num"); then
      log "  [warn] fetch failed for PR comments on $pr_id; skipping this sweep"
      PRS_FETCH_FAILED=$((PRS_FETCH_FAILED + 1))
      continue
    fi

    if has_consensus_sentinel "$body" "$sha"; then
      log "  [done] $pr_id (consensus already at this SHA)"
      continue
    fi

    if has_debate_sentinel "$body" "$sha"; then
      # A debate is not terminal — it converges only via the CEO resolution
      # sentinel `<!-- ceo-resolved: <sha> verdict: <...> -->` on the PR.
      resolved_v=$(sentinel_verdict "$body" "ceo-resolved" "$sha")
      if [[ -z "$resolved_v" ]]; then
        log "  [waiting] $pr_id (debate open — waiting for CEO adjudication)"
        continue
      fi
      case "$resolved_v" in
        approve|request-changes|block) ;;
        *)
          log "  [warn] $pr_id ceo-resolved sentinel carries unrecognized verdict '$resolved_v'; still waiting for a valid CEO adjudication"
          continue
          ;;
      esac
      if [[ "$resolved_v" == "approve" ]]; then
        close_review_issue_if_known "$repo" "$num" "$sha" "$body"
      fi
      # Non-approve: the CEO already owns rework from the adjudication —
      # record the resolved verdict and stop. No new outcome comment.
      if post_pr_comment "$repo" "$num" "CEO adjudication recorded: $resolved_v — debate resolved.

<!-- consensus: $sha verdict: $resolved_v -->"; then
        log "  [resolved] $pr_id (debate → $resolved_v)"
      else
        log "    [warn] resolution consensus comment not written for $GH_OWNER/$repo#$num; next sweep will retry"
      fi
      continue
    fi

    if ! pr_body_str=$(pr_body "$repo" "$num"); then
      log "  [warn] fetch failed for PR body on $pr_id; skipping this sweep"
      PRS_FETCH_FAILED=$((PRS_FETCH_FAILED + 1))
      continue
    fi
    author_uuid=$(original_author_id_from_body "$pr_body_str")
    author_mention=$(original_author_mention_from_body "$pr_body_str")
    peer_agent=$(peer_engineer_for_author "$author_uuid")

    evaluator_uuid=$(mention_agent_uuid "$EVALUATOR_MENTION")
    if [[ -n "$author_uuid" && -n "$evaluator_uuid" && "$author_uuid" == "$evaluator_uuid" ]]; then
      # Evaluator-authored PR: the adversarial lane must never self-review.
      # Both lanes are carried by the two Engineer instances (peer:
      # Engineer-A, adversarial checklist: Engineer-B); consensus accepts two
      # `engineer-reviewed` sentinels from two distinct review comments as
      # the two lanes (first = peer, second = adversarial).
      eng_verdicts=$(sentinel_verdicts_all "$body" "engineer-reviewed" "$sha")
      eng_count=0
      [[ -n "$eng_verdicts" ]] && eng_count=$(printf '%s\n' "$eng_verdicts" | grep -c .)
      if (( eng_count >= 2 )); then
        v_peer=$(printf '%s\n' "$eng_verdicts" | sed -n '1p')
        v_adv=$(printf '%s\n' "$eng_verdicts" | sed -n '2p')
        write_consensus "$repo" "$num" "$sha" "$v_peer" "$v_adv" "$body" "$author_uuid" "$author_mention" "engineer-pair"
      elif (( eng_count == 1 )); then
        log "  [need-adversarial-engineer] $pr_id (evaluator-authored; first engineer verdict=$eng_verdicts)"
        dispatch_review_request "$repo" "$num" "$sha" "$body" "$ENGINEER_B_AGENT" "adversarial-engineer" && REVIEWS_REQUESTED=$((REVIEWS_REQUESTED + 1))
      else
        log "  [need-engineer-first] $pr_id (evaluator-authored; peer=$ENGINEER_A_AGENT)"
        dispatch_review_request "$repo" "$num" "$sha" "$body" "$ENGINEER_A_AGENT" && REVIEWS_REQUESTED=$((REVIEWS_REQUESTED + 1))
      fi
      continue
    fi

    engineer_v=$(sentinel_verdict "$body" "engineer-reviewed" "$sha")
    evaluator_v=$(sentinel_verdict "$body" "evaluator-reviewed" "$sha")

    if [[ -n "$engineer_v" && -n "$evaluator_v" ]]; then
      write_consensus "$repo" "$num" "$sha" "$engineer_v" "$evaluator_v" "$body" "$author_uuid" "$author_mention"
    elif [[ -n "$engineer_v" ]]; then
      log "  [need-evaluator] $pr_id (engineer=$engineer_v)"
      dispatch_review_request "$repo" "$num" "$sha" "$body" "$EVALUATOR_AGENT" && REVIEWS_REQUESTED=$((REVIEWS_REQUESTED + 1))
    elif [[ -n "$evaluator_v" ]]; then
      log "  [need-engineer] $pr_id (evaluator=$evaluator_v peer=$peer_agent)"
      dispatch_review_request "$repo" "$num" "$sha" "$body" "$peer_agent" && REVIEWS_REQUESTED=$((REVIEWS_REQUESTED + 1))
    else
      log "  [need-engineer-first] $pr_id (peer=$peer_agent)"
      dispatch_review_request "$repo" "$num" "$sha" "$body" "$peer_agent" && REVIEWS_REQUESTED=$((REVIEWS_REQUESTED + 1))
    fi
  done <<<"$prs_raw"
done <<<"$REPOS"

log "[summary] repos_ok=$REPOS_OK repos_errored=$REPOS_ERRORED prs_seen=$PRS_TOTAL prs_fetch_failed=$PRS_FETCH_FAILED"
log "[done] sweep complete: review_requests=$REVIEWS_REQUESTED"
