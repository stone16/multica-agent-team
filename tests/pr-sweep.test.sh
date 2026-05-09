#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/.github/scripts/pr-sweep.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq -- "$expected" "$file"; then
    printf 'Expected to find:\n%s\n\nin %s:\n' "$expected" "$file" >&2
    sed -n '1,220p' "$file" >&2
    fail "missing expected content"
  fi
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  if grep -Fq -- "$unexpected" "$file"; then
    printf 'Did not expect to find:\n%s\n\nin %s:\n' "$unexpected" "$file" >&2
    sed -n '1,220p' "$file" >&2
    fail "found unexpected content"
  fi
}

assert_file_count() {
  local dir="$1"
  local expected="$2"
  local actual
  actual=$(find "$dir" -type f -name 'issue-*.description.md' | wc -l | tr -d ' ')
  [[ "$actual" == "$expected" ]] || fail "expected $expected issue descriptions, got $actual"
}

assert_comment_count() {
  local dir="$1"
  local expected="$2"
  local actual
  actual=$(find "$dir" -type f -name 'issue-comment-*.md' | wc -l | tr -d ' ')
  [[ "$actual" == "$expected" ]] || fail "expected $expected issue comments, got $actual"
}

assert_pr_comment_count() {
  local dir="$1"
  local expected="$2"
  local actual
  actual=$(find "$dir" -type f -name 'pr-comment-*.md' | wc -l | tr -d ' ')
  [[ "$actual" == "$expected" ]] || fail "expected $expected PR comments, got $actual"
}

assert_update_count() {
  local dir="$1"
  local expected="$2"
  local actual
  actual=$(find "$dir" -type f -name 'issue-update-*.args' | wc -l | tr -d ' ')
  [[ "$actual" == "$expected" ]] || fail "expected $expected issue updates, got $actual"
}

assert_status() {
  local dir="$1"
  local expected="$2"
  local actual
  actual="$(cat "$dir/captures/status")"
  [[ "$actual" == "$expected" ]] || {
    printf 'stdout:\n' >&2
    sed -n '1,220p' "$dir/stdout.log" >&2
    printf 'stderr:\n' >&2
    sed -n '1,220p' "$dir/stderr.log" >&2
    fail "expected exit status $expected, got $actual"
  }
}

run_sweep_with_stubs() {
  local scenario="$1"
  local expected_status="${PR_SWEEP_EXPECT_STATUS:-0}"
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/bin" "$tmp/captures"

  cat >"$tmp/bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

scenario="${PR_SWEEP_TEST_SCENARIO:?}"

if [[ "$1 $2" == "repo list" ]]; then
  printf 'sample-repo\n'
  exit 0
fi

if [[ "$1 $2" == "pr list" ]]; then
  printf '12\tdeadbeef\tcontributor\n'
  exit 0
fi

if [[ "$1 $2" == "pr diff" ]]; then
  printf 'src/app.ts\n'
  exit 0
fi

if [[ "$1 $2" == "pr view" ]]; then
  if printf '%s\n' "$*" | grep -Fq -- "--json body"; then
    if [[ "$scenario" == "reviewed-with-action-items-unrelated-author-mention" ]]; then
      printf 'Related Multica issue: [STO-42](mention://issue/2a16cdfb-f0e2-4d71-8dfd-a156a9b02b2e)\nThanks to [@Hao](mention://agent/f804cbdf-33d3-4a98-a6b5-2f7b796915b6) for early feedback.\n'
    elif [[ "$scenario" == "reviewed-with-action-items-no-related-issue" ]]; then
      printf 'No related Multica issue yet.\n'
    else
      printf 'Related Multica issue: [STO-42](mention://issue/2a16cdfb-f0e2-4d71-8dfd-a156a9b02b2e)\n'
    fi
    exit 0
  fi

  if printf '%s\n' "$*" | grep -Fq -- "hao-reviewed: deadbeef"; then
    if [[ "$scenario" == "reviewed-debate" ]]; then
      cat <<'COMMENTS'
Verdict: request-changes

- src/app.ts:7 -- missing regression test.

<!-- hao-reviewed: deadbeef verdict: request-changes -->
COMMENTS
    else
      cat <<'COMMENTS'
Verdict: request-changes

- src/app.ts:7 -- missing regression test.

<!-- hao-reviewed: deadbeef verdict: request-changes -->
COMMENTS
    fi
    exit 0
  fi

  if printf '%s\n' "$*" | grep -Fq -- "dustin-reviewed: deadbeef"; then
    if [[ "$scenario" == "reviewed-debate" ]]; then
      cat <<'COMMENTS'
Verdict: approve

Security findings: none.
Performance findings: none.

<!-- dustin-reviewed: deadbeef verdict: approve -->
COMMENTS
    else
      cat <<'COMMENTS'
Verdict: request-changes

Security findings: none.
Performance findings:
- [missing-timeout] src/app.ts:12 -- outbound call has no timeout.

<!-- dustin-reviewed: deadbeef verdict: request-changes -->
COMMENTS
    fi
    exit 0
  fi

  if [[ "$scenario" == "unreviewed-review-issue-exists" ]]; then
    cat <<'COMMENTS'
<!-- multica-pr-review-issue: 11111111-1111-1111-1111-000000000001 -->
COMMENTS
  elif [[ "$scenario" == "reviewed-hao-only-review-issue-exists" ]]; then
    cat <<'COMMENTS'
<!-- multica-pr-review-issue: 11111111-1111-1111-1111-000000000001 -->
Verdict: request-changes

- src/app.ts:7 -- missing regression test.

<!-- hao-reviewed: deadbeef verdict: request-changes -->
COMMENTS
  elif [[ "$scenario" == "reviewed-with-action-items-review-issue-exists" ]]; then
    cat <<'COMMENTS'
<!-- multica-pr-review-issue: 11111111-1111-1111-1111-000000000001 -->
Verdict: request-changes

- src/app.ts:7 -- missing regression test.

<!-- hao-reviewed: deadbeef verdict: request-changes -->
Verdict: request-changes

Security findings: none.
Performance findings:
- [missing-timeout] src/app.ts:12 -- outbound call has no timeout.

<!-- dustin-reviewed: deadbeef verdict: request-changes -->
COMMENTS
  elif [[ "$scenario" == "reviewed-approve-approve-review-issue-exists" ]]; then
    cat <<'COMMENTS'
<!-- multica-pr-review-issue: 11111111-1111-1111-1111-000000000001 -->
Verdict: approve

What I checked:
- src/app.ts:1 -- change is covered.

<!-- hao-reviewed: deadbeef verdict: approve -->
Verdict: approve

Security findings: none.
Performance findings: none.

<!-- dustin-reviewed: deadbeef verdict: approve -->
COMMENTS
  elif [[ "$scenario" == "reviewed-with-action-items" || "$scenario" == "reviewed-with-action-items-comment-fails" ]]; then
    cat <<'COMMENTS'
Verdict: request-changes

- src/app.ts:7 -- missing regression test.

<!-- hao-reviewed: deadbeef verdict: request-changes -->
Verdict: request-changes

Security findings: none.
Performance findings:
- [missing-timeout] src/app.ts:12 -- outbound call has no timeout.

<!-- dustin-reviewed: deadbeef verdict: request-changes -->
COMMENTS
  elif [[ "$scenario" == "reviewed-debate" ]]; then
    cat <<'COMMENTS'
Verdict: request-changes

- src/app.ts:7 -- missing regression test.

<!-- hao-reviewed: deadbeef verdict: request-changes -->
Verdict: approve

Security findings: none.
Performance findings: none.

<!-- dustin-reviewed: deadbeef verdict: approve -->
COMMENTS
  elif [[ "$scenario" == "reviewed-with-action-items-no-related-issue" ]]; then
    cat <<'COMMENTS'
Verdict: request-changes

- src/app.ts:7 -- missing regression test.

<!-- hao-reviewed: deadbeef verdict: request-changes -->
Verdict: request-changes

Security findings: none.
Performance findings:
- [missing-timeout] src/app.ts:12 -- outbound call has no timeout.

<!-- dustin-reviewed: deadbeef verdict: request-changes -->
COMMENTS
  elif [[ "$scenario" == "reviewed-approve-approve" ]]; then
    cat <<'COMMENTS'
Verdict: approve

What I checked:
- src/app.ts:1 -- change is covered.

<!-- hao-reviewed: deadbeef verdict: approve -->
Verdict: approve

Security findings: none.
Performance findings: none.

<!-- dustin-reviewed: deadbeef verdict: approve -->
COMMENTS
  elif [[ "$scenario" == "reviewed-with-action-items-iter-cap" ]]; then
    cat <<'COMMENTS'
Consensus reached: request-changes.

<!-- consensus: 1111111111111111111111111111111111111111 verdict: request-changes -->
Consensus reached: request-changes.

<!-- consensus: 2222222222222222222222222222222222222222 verdict: request-changes -->
Consensus reached: request-changes.

<!-- consensus: 3333333333333333333333333333333333333333 verdict: request-changes -->
Verdict: request-changes

- src/app.ts:7 -- still missing regression test.

<!-- hao-reviewed: deadbeef verdict: request-changes -->
Verdict: request-changes

Security findings: none.
Performance findings:
- [missing-timeout] src/app.ts:12 -- outbound call still has no timeout.

<!-- dustin-reviewed: deadbeef verdict: request-changes -->
COMMENTS
  elif [[ "$scenario" == "reviewed-with-action-items-unrelated-author-mention" ]]; then
    cat <<'COMMENTS'
Verdict: request-changes

- src/app.ts:7 -- missing regression test.

<!-- hao-reviewed: deadbeef verdict: request-changes -->
Verdict: request-changes

Security findings: none.
Performance findings:
- [missing-timeout] src/app.ts:12 -- outbound call has no timeout.

<!-- dustin-reviewed: deadbeef verdict: request-changes -->
COMMENTS
  elif [[ "$scenario" == "reviewed-with-prose-mention-not-counted" ]]; then
    # Old routing counted prior consensus sentinels and sometimes went back
    # to the author. New routing ignores this for follow-up and pings CTO.
    cat <<'COMMENTS'
Earlier we noted the consensus: feedfeedfeedfeedfeedfeedfeedfeedfeedfeed verdict: request-changes call was wrong.

A reviewer quoted: "the marker `consensus: cafebabecafebabecafebabecafebabecafebabe verdict: block` got mangled in transit"

The actual prior sentinel:

<!-- consensus: 1111111111111111111111111111111111111111 verdict: request-changes -->

Now the new round:

Verdict: request-changes

- src/app.ts:7 -- still missing regression test.

<!-- hao-reviewed: deadbeef verdict: request-changes -->
Verdict: request-changes

Security findings: none.

<!-- dustin-reviewed: deadbeef verdict: request-changes -->
COMMENTS
  fi
  exit 0
fi

if [[ "$1 $2" == "pr comment" ]]; then
  if [[ "${PR_SWEEP_PR_COMMENT_FAIL:-0}" == "1" ]]; then
    printf 'simulated pr comment failure\n' >&2
    exit 1
  fi
  idx_file="$PR_SWEEP_CAPTURE_DIR/pr-comment-count"
  idx=0
  if [[ -f "$idx_file" ]]; then
    idx="$(cat "$idx_file")"
  fi
  idx=$((idx + 1))
  printf '%s' "$idx" >"$idx_file"

  cat >"$PR_SWEEP_CAPTURE_DIR/pr-comment-${idx}.md"
  cp "$PR_SWEEP_CAPTURE_DIR/pr-comment-${idx}.md" "$PR_SWEEP_CAPTURE_DIR/pr-comment.md"
  exit 0
fi

printf 'unexpected gh invocation: %s\n' "$*" >&2
exit 64
GH

cat >"$tmp/bin/multica" <<'MULTICA'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1 $2" == "issue comment" && "${3:-}" == "list" ]]; then
  if [[ "$PR_SWEEP_TEST_SCENARIO" == "unreviewed-review-issue-exists" ]]; then
    printf '[{"content":"<!-- multica-review-requested: deadbeef agent: hao -->"}]\n'
  elif [[ "$PR_SWEEP_TEST_SCENARIO" == "reviewed-with-action-items-review-issue-exists" && "${PR_SWEEP_EXISTING_ORIGIN_COMMENT:-0}" == "1" ]]; then
    printf '[{"content":"<!-- multica-review-dispatched: deadbeef -->"}]\n'
  elif [[ "${PR_SWEEP_EXISTING_ORIGIN_COMMENT:-0}" == "1" ]]; then
    printf '[{"content":"<!-- multica-review-dispatched: deadbeef -->"}]\n'
  else
    printf '[]\n'
  fi
  exit 0
fi

if [[ "$1 $2" == "issue comment" && "${3:-}" == "add" ]]; then
  if [[ "${PR_SWEEP_MULTICA_FAIL:-0}" == "1" ]]; then
    printf 'simulated multica issue comment failure\n' >&2
    exit 1
  fi

  idx_file="$PR_SWEEP_CAPTURE_DIR/issue-comment-count"
  idx=0
  if [[ -f "$idx_file" ]]; then
    idx="$(cat "$idx_file")"
  fi
  idx=$((idx + 1))
  printf '%s' "$idx" >"$idx_file"

  printf '%s\n' "$*" >"$PR_SWEEP_CAPTURE_DIR/issue-comment-${idx}.args"
  cat >"$PR_SWEEP_CAPTURE_DIR/issue-comment-${idx}.md"
  printf '{"id":"issue-comment-%s"}\n' "$idx"
  exit 0
fi

if [[ "$1 $2" == "issue update" ]]; then
  idx_file="$PR_SWEEP_CAPTURE_DIR/issue-update-count"
  idx=0
  if [[ -f "$idx_file" ]]; then
    idx="$(cat "$idx_file")"
  fi
  idx=$((idx + 1))
  printf '%s' "$idx" >"$idx_file"

  printf '%s\n' "$*" >"$PR_SWEEP_CAPTURE_DIR/issue-update-${idx}.args"
  printf '{"id":"%s"}\n' "${3:-unknown}"
  exit 0
fi

[[ "$1 $2" == "issue create" ]] || {
  if [[ "$1 $2" == "issue list" ]]; then
    printf '[]\n'
    exit 0
  fi
  printf 'unexpected multica invocation: %s\n' "$*" >&2
  exit 64
}

if [[ "${PR_SWEEP_MULTICA_FAIL:-0}" == "1" ]]; then
  printf 'simulated multica issue create failure\n' >&2
  exit 1
fi

idx_file="$PR_SWEEP_CAPTURE_DIR/issue-count"
idx=0
if [[ -f "$idx_file" ]]; then
  idx="$(cat "$idx_file")"
fi
idx=$((idx + 1))
printf '%s' "$idx" >"$idx_file"

printf '%s\n' "$*" >"$PR_SWEEP_CAPTURE_DIR/issue-${idx}.args"
cat >"$PR_SWEEP_CAPTURE_DIR/issue-${idx}.description.md"
printf '{"id":"11111111-1111-1111-1111-00000000000%s"}\n' "$idx"
MULTICA

  chmod +x "$tmp/bin/gh" "$tmp/bin/multica"

  set +e
  PR_SWEEP_TEST_SCENARIO="$scenario" \
    PR_SWEEP_CAPTURE_DIR="$tmp/captures" \
    PR_SWEEP_PR_COMMENT_FAIL="${PR_SWEEP_PR_COMMENT_FAIL:-0}" \
    PR_SWEEP_MULTICA_FAIL="${PR_SWEEP_MULTICA_FAIL:-0}" \
    PR_SWEEP_EXISTING_ORIGIN_COMMENT="${PR_SWEEP_EXISTING_ORIGIN_COMMENT:-0}" \
    LC_ALL=C \
    LANG=C \
    PATH="$tmp/bin:$PATH" \
    GH_OWNER="stone16" \
    HAO_AGENT="Hao" \
    DUSTIN_AGENT="Dustin" \
    CTO_AGENT="Stometa" \
    bash "$SCRIPT" >"$tmp/stdout.log" 2>"$tmp/stderr.log"
  status=$?
  set -e
  printf '%s' "$status" >"$tmp/captures/status"
  [[ "$status" == "$expected_status" ]] || {
    printf 'stdout:\n' >&2
    sed -n '1,220p' "$tmp/stdout.log" >&2
    printf 'stderr:\n' >&2
    sed -n '1,220p' "$tmp/stderr.log" >&2
    fail "expected sweep status $expected_status, got $status"
  }

  printf '%s\n' "$tmp"
}

assert_line_before() {
  local file="$1"
  local earlier="$2"
  local later="$3"
  local earlier_n later_n
  earlier_n=$(grep -nF -- "$earlier" "$file" | head -1 | cut -d: -f1)
  later_n=$(grep -nF -- "$later" "$file" | head -1 | cut -d: -f1)
  if [[ -z "$earlier_n" || -z "$later_n" ]]; then
    fail "assert_line_before: missing anchor in $file (earlier=$earlier_n later=$later_n)"
  fi
  if (( earlier_n >= later_n )); then
    printf 'Expected line %s ("%s")\nto appear BEFORE line %s ("%s")\nin %s:\n' \
      "$earlier_n" "$earlier" "$later_n" "$later" "$file" >&2
    sed -n '1,220p' "$file" >&2
    fail "ordering violation"
  fi
}

test_unreviewed_pr_creates_one_review_issue_for_first_reviewer() {
  local tmp
  tmp="$(run_sweep_with_stubs unreviewed)"

  assert_file_count "$tmp/captures" 1
  assert_comment_count "$tmp/captures" 1
  assert_update_count "$tmp/captures" 1
  assert_pr_comment_count "$tmp/captures" 1
  assert_contains "$tmp/captures/issue-1.args" "--assignee Hao"
  assert_contains "$tmp/captures/issue-update-1.args" "--assignee Hao"
  assert_contains "$tmp/captures/issue-1.args" "--title PR review - stone16/sample-repo#12"
  assert_contains "$tmp/captures/issue-1.description.md" "[stone16/sample-repo#12](https://github.com/stone16/sample-repo/pull/12) @ deadbeef"
  assert_contains "$tmp/captures/issue-1.description.md" "This is the single Multica thread for this PR review."
  assert_contains "$tmp/captures/issue-comment-1.md" "Hao review is requested for [stone16/sample-repo#12](https://github.com/stone16/sample-repo/pull/12) @ deadbeef."
  assert_contains "$tmp/captures/issue-1.description.md" "Both reviewers are required on every PR; this is not a rotation."
  assert_contains "$tmp/captures/issue-1.description.md" "Documentation-only PRs receive the same dual review"
  assert_contains "$tmp/captures/issue-1.description.md" "Minimum review bar is identical for both reviewers:"
  assert_contains "$tmp/captures/issue-1.description.md" "multica repo checkout https://github.com/<owner>/<repo>.git --ref <head-sha>"
  assert_contains "$tmp/captures/issue-1.description.md" "If \`multica repo checkout\` fails because the SHA is unreachable"
  assert_contains "$tmp/captures/issue-1.description.md" "A sentinel must always reflect a review actually conducted on the SHA it tags"
  assert_contains "$tmp/captures/issue-1.description.md" "Use the PR link above in your PR comment and in this Multica issue summary"
  assert_not_contains "$tmp/captures/issue-1.description.md" "non-docs production-code"
  assert_contains "$tmp/captures/issue-comment-1.md" "<!-- multica-review-requested: deadbeef agent: hao -->"
  assert_contains "$tmp/captures/pr-comment-1.md" "<!-- multica-pr-review-issue: 11111111-1111-1111-1111-000000000001 -->"

  # Race-condition guard: the headRefOid pin must appear BEFORE the worktree
  # checkout, otherwise an agent can review a stale SHA and post a sentinel
  # tagged with a newer SHA it never actually reviewed.
  assert_line_before "$tmp/captures/issue-1.description.md" \
    "gh pr view <num> --repo <owner/repo> --json headRefOid --jq .headRefOid" \
    "multica repo checkout https://github.com/<owner>/<repo>.git --ref <head-sha>"
}

test_existing_review_issue_marker_prevents_duplicate_review_request() {
  local tmp
  tmp="$(run_sweep_with_stubs unreviewed-review-issue-exists)"

  assert_file_count "$tmp/captures" 0
  assert_comment_count "$tmp/captures" 0
  assert_update_count "$tmp/captures" 1
  assert_pr_comment_count "$tmp/captures" 0
  assert_contains "$tmp/captures/issue-update-1.args" "11111111-1111-1111-1111-000000000001"
  assert_contains "$tmp/captures/issue-update-1.args" "--assignee Hao"
  assert_contains "$tmp/stderr.log" "review-request=exists 11111111-1111-1111-1111-000000000001 stone16/sample-repo#12@deadbeef"
}

test_after_hao_review_routes_dustin_in_same_review_issue() {
  local tmp
  tmp="$(run_sweep_with_stubs reviewed-hao-only-review-issue-exists)"

  assert_file_count "$tmp/captures" 0
  assert_comment_count "$tmp/captures" 1
  assert_update_count "$tmp/captures" 1
  assert_pr_comment_count "$tmp/captures" 0
  assert_contains "$tmp/captures/issue-update-1.args" "11111111-1111-1111-1111-000000000001"
  assert_contains "$tmp/captures/issue-update-1.args" "--assignee Dustin"
  assert_contains "$tmp/captures/issue-comment-1.md" "Dustin review is requested for [stone16/sample-repo#12](https://github.com/stone16/sample-repo/pull/12) @ deadbeef."
  assert_contains "$tmp/captures/issue-comment-1.md" "<!-- multica-review-requested: deadbeef agent: dustin -->"
}

test_action_items_route_to_cto_in_pr_review_issue() {
  local tmp
  tmp="$(run_sweep_with_stubs reviewed-with-action-items)"

  assert_file_count "$tmp/captures" 1
  assert_comment_count "$tmp/captures" 1
  assert_update_count "$tmp/captures" 1
  assert_pr_comment_count "$tmp/captures" 2
  assert_contains "$tmp/captures/issue-comment-1.args" "11111111-1111-1111-1111-000000000001"
  assert_contains "$tmp/captures/issue-update-1.args" "--assignee Stometa"
  assert_contains "$tmp/captures/issue-comment-1.md" "[@CTO](mention://agent/2669622c-24fd-4254-bab7-2a7c2a5c5e12)"
  assert_not_contains "$tmp/captures/issue-comment-1.md" "[@author](mention://agent/"
  assert_contains "$tmp/captures/issue-comment-1.md" "- PR: https://github.com/stone16/sample-repo/pull/12"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Head commit: deadbeef"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Final verdict: consensus: request-changes"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Hao verdict: request-changes"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Dustin verdict: request-changes"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Action: cto-followup"
  assert_contains "$tmp/captures/issue-comment-1.md" "missing regression test."
  assert_contains "$tmp/captures/issue-comment-1.md" "outbound call has no timeout."
  assert_not_contains "$tmp/captures/issue-comment-1.md" "hao-reviewed:"
  assert_not_contains "$tmp/captures/issue-comment-1.md" "dustin-reviewed:"
  assert_contains "$tmp/captures/issue-comment-1.md" "<!-- multica-review-dispatched: deadbeef -->"
  assert_contains "$tmp/captures/pr-comment-1.md" "<!-- multica-pr-review-issue: 11111111-1111-1111-1111-000000000001 -->"
  assert_contains "$tmp/captures/pr-comment.md" "<!-- consensus: deadbeef verdict: request-changes -->"
}

test_missing_related_issue_still_routes_to_cto_review_issue() {
  local tmp
  tmp="$(run_sweep_with_stubs reviewed-with-action-items-no-related-issue)"

  assert_file_count "$tmp/captures" 1
  assert_comment_count "$tmp/captures" 1
  assert_update_count "$tmp/captures" 1
  assert_pr_comment_count "$tmp/captures" 2
  assert_contains "$tmp/captures/issue-comment-1.md" "[@CTO](mention://agent/2669622c-24fd-4254-bab7-2a7c2a5c5e12)"
  assert_not_contains "$tmp/captures/issue-comment-1.md" "[@author](mention://agent/"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Action: cto-followup"
  assert_not_contains "$tmp/captures/pr-comment-1.md" "Originating Multica issue link is missing."
  assert_contains "$tmp/captures/pr-comment-1.md" "<!-- multica-pr-review-issue: 11111111-1111-1111-1111-000000000001 -->"
  assert_contains "$tmp/captures/pr-comment.md" "<!-- consensus: deadbeef verdict: request-changes -->"
}

test_unrelated_author_mentions_are_ignored_because_cto_always_owns_followup() {
  local tmp
  tmp="$(run_sweep_with_stubs reviewed-with-action-items-unrelated-author-mention)"

  assert_file_count "$tmp/captures" 1
  assert_comment_count "$tmp/captures" 1
  assert_update_count "$tmp/captures" 1
  assert_contains "$tmp/captures/issue-comment-1.md" "[@CTO](mention://agent/2669622c-24fd-4254-bab7-2a7c2a5c5e12)"
  assert_not_contains "$tmp/captures/issue-comment-1.md" "[@author](mention://agent/"
  assert_not_contains "$tmp/captures/issue-comment-1.md" "f804cbdf-33d3-4a98-a6b5-2f7b796915b6"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Action: cto-followup"
  assert_contains "$tmp/captures/pr-comment.md" "<!-- consensus: deadbeef verdict: request-changes -->"
}

test_prior_iterations_do_not_route_back_to_author() {
  local tmp
  tmp="$(run_sweep_with_stubs reviewed-with-prose-mention-not-counted)"

  assert_file_count "$tmp/captures" 1
  assert_comment_count "$tmp/captures" 1
  assert_update_count "$tmp/captures" 1
  assert_contains "$tmp/captures/issue-comment-1.md" "[@CTO](mention://agent/2669622c-24fd-4254-bab7-2a7c2a5c5e12)"
  assert_not_contains "$tmp/captures/issue-comment-1.md" "[@author](mention://agent/"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Action: cto-followup"
  assert_not_contains "$tmp/captures/issue-comment-1.md" "max-iterations-escalation"
}

test_approve_consensus_closes_existing_review_issue_without_cto() {
  local tmp
  tmp="$(run_sweep_with_stubs reviewed-approve-approve-review-issue-exists)"

  assert_file_count "$tmp/captures" 0
  assert_comment_count "$tmp/captures" 0
  assert_update_count "$tmp/captures" 1
  assert_contains "$tmp/captures/issue-update-1.args" "--status done"
  assert_not_contains "$tmp/captures/issue-update-1.args" "--assignee"
  assert_contains "$tmp/captures/pr-comment.md" "<!-- consensus: deadbeef verdict: approve -->"
}

test_debate_routes_to_cto_in_pr_review_issue() {
  local tmp
  tmp="$(run_sweep_with_stubs reviewed-debate)"

  assert_file_count "$tmp/captures" 1
  assert_comment_count "$tmp/captures" 1
  assert_update_count "$tmp/captures" 1
  assert_contains "$tmp/captures/issue-comment-1.md" "[@CTO](mention://agent/2669622c-24fd-4254-bab7-2a7c2a5c5e12)"
  assert_not_contains "$tmp/captures/issue-comment-1.md" "[@author](mention://agent/"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Action: cto-debate"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Final verdict: debate"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Hao verdict: request-changes"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Dustin verdict: approve"
  assert_not_contains "$tmp/captures/issue-comment-1.md" "hao-reviewed:"
  assert_not_contains "$tmp/captures/issue-comment-1.md" "dustin-reviewed:"
  assert_contains "$tmp/captures/pr-comment.md" "<!-- debate: deadbeef -->"
}

test_existing_review_outcome_prevents_duplicate_when_final_comment_fails() {
  local tmp
  tmp="$(PR_SWEEP_EXISTING_ORIGIN_COMMENT=1 PR_SWEEP_PR_COMMENT_FAIL=1 run_sweep_with_stubs reviewed-with-action-items-review-issue-exists)"

  assert_status "$tmp" 0
  assert_file_count "$tmp/captures" 0
  assert_comment_count "$tmp/captures" 0
  [[ ! -f "$tmp/captures/pr-comment.md" ]] || fail "final PR sentinel unexpectedly succeeded"
  assert_contains "$tmp/stderr.log" "[warn] post_pr_comment failed for stone16/sample-repo#12"
  assert_contains "$tmp/stderr.log" "review-outcome=exists 11111111-1111-1111-1111-000000000001 stone16/sample-repo#12@deadbeef"
}

test_multica_dispatch_failure_does_not_abort_sweep() {
  local tmp
  tmp="$(PR_SWEEP_MULTICA_FAIL=1 run_sweep_with_stubs unreviewed)"

  assert_status "$tmp" 0
  assert_file_count "$tmp/captures" 0
  assert_comment_count "$tmp/captures" 0
  assert_contains "$tmp/stderr.log" "[warn] ensure_review_issue failed for stone16/sample-repo#12"
}

test_review_outcome_failure_does_not_write_final_sentinel() {
  local tmp
  tmp="$(PR_SWEEP_MULTICA_FAIL=1 run_sweep_with_stubs reviewed-with-action-items-review-issue-exists)"

  assert_status "$tmp" 0
  assert_file_count "$tmp/captures" 0
  assert_comment_count "$tmp/captures" 0
  [[ ! -f "$tmp/captures/pr-comment.md" ]] || fail "final PR sentinel was written even though CTO delegation failed"
  assert_contains "$tmp/stderr.log" "[warn] post_review_outcome_comment failed for stone16/sample-repo#12"
}

test_existing_review_outcome_allows_final_comment_without_duplicate() {
  local tmp
  tmp="$(PR_SWEEP_EXISTING_ORIGIN_COMMENT=1 PR_SWEEP_MULTICA_FAIL=1 run_sweep_with_stubs reviewed-with-action-items-review-issue-exists)"

  assert_status "$tmp" 0
  assert_file_count "$tmp/captures" 0
  assert_comment_count "$tmp/captures" 0
  assert_contains "$tmp/captures/pr-comment.md" "<!-- consensus: deadbeef verdict: request-changes -->"
  assert_contains "$tmp/stderr.log" "review-outcome=exists 11111111-1111-1111-1111-000000000001 stone16/sample-repo#12@deadbeef"
}

test_unreviewed_pr_creates_one_review_issue_for_first_reviewer
test_existing_review_issue_marker_prevents_duplicate_review_request
test_after_hao_review_routes_dustin_in_same_review_issue
test_action_items_route_to_cto_in_pr_review_issue
test_missing_related_issue_still_routes_to_cto_review_issue
test_unrelated_author_mentions_are_ignored_because_cto_always_owns_followup
test_prior_iterations_do_not_route_back_to_author
test_approve_consensus_closes_existing_review_issue_without_cto
test_debate_routes_to_cto_in_pr_review_issue
test_existing_review_outcome_prevents_duplicate_when_final_comment_fails
test_multica_dispatch_failure_does_not_abort_sweep
test_review_outcome_failure_does_not_write_final_sentinel
test_existing_review_outcome_allows_final_comment_without_duplicate
printf 'PASS: pr-sweep PR issue routing tests\n'
