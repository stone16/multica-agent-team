#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/.github/scripts/pr-sweep.sh"

# Fake roster identity used across the suite. UUIDs are test fixtures only.
ENGINEER_A_UUID="aaaaaaaa-0000-0000-0000-000000000001"
ENGINEER_B_UUID="bbbbbbbb-0000-0000-0000-000000000001"
EVALUATOR_UUID="eeeeeeee-0000-0000-0000-000000000001"
CEO_UUID="cccccccc-0000-0000-0000-000000000001"
CEO_MENTION_LINK="[@CEO](mention://agent/$CEO_UUID)"
ENGINEER_A_MENTION_LINK="[@Engineer-A](mention://agent/$ENGINEER_A_UUID)"
ENGINEER_B_MENTION_LINK="[@Engineer-B](mention://agent/$ENGINEER_B_UUID)"
EVALUATOR_MENTION_LINK="[@Evaluator](mention://agent/$EVALUATOR_UUID)"

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
  if [[ "${PR_SWEEP_GH_VIEW_FAIL:-0}" == "1" ]]; then
    printf 'simulated gh pr view failure\n' >&2
    exit 1
  fi

  if printf '%s\n' "$*" | grep -Fq -- "--json body"; then
    case "$scenario" in
      unreviewed-author-engineer-a|reviewed-with-action-items|reviewed-with-action-items-review-issue-exists|reviewed-with-action-items-iter-cap|reviewed-with-prose-mention-not-counted)
        printf 'Originating Multica issue: [STO-42](mention://issue/12121212-1212-1212-1212-121212121212)\nOriginal author: [@Engineer-A](mention://agent/aaaaaaaa-0000-0000-0000-000000000001)\n'
        ;;
      unreviewed-author-engineer-b)
        printf 'Originating Multica issue: [STO-42](mention://issue/12121212-1212-1212-1212-121212121212)\nOriginal author: [@Engineer-B](mention://agent/bbbbbbbb-0000-0000-0000-000000000001)\n'
        ;;
      unreviewed-author-evaluator|evaluator-author-one-engineer-review|evaluator-author-two-engineer-reviews)
        printf 'Originating Multica issue: [STO-42](mention://issue/12121212-1212-1212-1212-121212121212)\nOriginal author: [@Evaluator](mention://agent/eeeeeeee-0000-0000-0000-000000000001)\n'
        ;;
      reviewed-with-action-items-unrelated-author-mention)
        printf 'Originating Multica issue: [STO-42](mention://issue/12121212-1212-1212-1212-121212121212)\nThanks to [@Engineer-B](mention://agent/bbbbbbbb-0000-0000-0000-000000000001) for early feedback.\n'
        ;;
      *)
        printf 'Originating Multica issue: [STO-42](mention://issue/12121212-1212-1212-1212-121212121212)\n'
        ;;
    esac
    exit 0
  fi

  if printf '%s\n' "$*" | grep -Fq -- "engineer-reviewed: deadbeef"; then
    if [[ "$scenario" == "evaluator-author-two-engineer-reviews" ]]; then
      # Pair mode: the sweep fetches the peer review with [-2] and the
      # adversarial review with [-1] on the same sentinel name.
      if printf '%s\n' "$*" | grep -Fq -- "[-2]"; then
        cat <<'COMMENTS'
Verdict: request-changes

- src/app.ts:7 -- missing regression test.

<!-- engineer-reviewed: deadbeef verdict: request-changes -->
COMMENTS
      else
        cat <<'COMMENTS'
Verdict: request-changes

- src/app.ts:12 -- adversarial input path unguarded.

<!-- engineer-reviewed: deadbeef verdict: request-changes -->
COMMENTS
      fi
      exit 0
    fi
    if [[ "$scenario" == "reviewed-debate" ]]; then
      cat <<'COMMENTS'
Verdict: request-changes

- src/app.ts:7 -- missing regression test.

<!-- engineer-reviewed: deadbeef verdict: request-changes -->
COMMENTS
    else
      cat <<'COMMENTS'
Verdict: request-changes

- src/app.ts:7 -- missing regression test.

<!-- engineer-reviewed: deadbeef verdict: request-changes -->
COMMENTS
    fi
    exit 0
  fi

  if printf '%s\n' "$*" | grep -Fq -- "evaluator-reviewed: deadbeef"; then
    if [[ "$scenario" == "reviewed-debate" ]]; then
      cat <<'COMMENTS'
Verdict: approve

Security findings: none.
Performance findings: none.

<!-- evaluator-reviewed: deadbeef verdict: approve -->
COMMENTS
    else
      cat <<'COMMENTS'
Verdict: request-changes

Security findings: none.
Performance findings:
- [missing-timeout] src/app.ts:12 -- outbound call has no timeout.

<!-- evaluator-reviewed: deadbeef verdict: request-changes -->
COMMENTS
    fi
    exit 0
  fi

  if [[ "$scenario" == "unreviewed-review-issue-exists" ]]; then
    cat <<'COMMENTS'
<!-- multica-pr-review-issue: 11111111-1111-1111-1111-000000000001 -->
COMMENTS
  elif [[ "$scenario" == "reviewed-engineer-only-review-issue-exists" ]]; then
    cat <<'COMMENTS'
<!-- multica-pr-review-issue: 11111111-1111-1111-1111-000000000001 -->
Verdict: request-changes

- src/app.ts:7 -- missing regression test.

<!-- engineer-reviewed: deadbeef verdict: request-changes -->
COMMENTS
  elif [[ "$scenario" == "reviewed-with-action-items-review-issue-exists" ]]; then
    cat <<'COMMENTS'
<!-- multica-pr-review-issue: 11111111-1111-1111-1111-000000000001 -->
Verdict: request-changes

- src/app.ts:7 -- missing regression test.

<!-- engineer-reviewed: deadbeef verdict: request-changes -->
Verdict: request-changes

Security findings: none.
Performance findings:
- [missing-timeout] src/app.ts:12 -- outbound call has no timeout.

<!-- evaluator-reviewed: deadbeef verdict: request-changes -->
COMMENTS
  elif [[ "$scenario" == "reviewed-approve-approve-review-issue-exists" ]]; then
    cat <<'COMMENTS'
<!-- multica-pr-review-issue: 11111111-1111-1111-1111-000000000001 -->
Verdict: approve

What I checked:
- src/app.ts:1 -- change is covered.

<!-- engineer-reviewed: deadbeef verdict: approve -->
Verdict: approve

Security findings: none.
Performance findings: none.

<!-- evaluator-reviewed: deadbeef verdict: approve -->
COMMENTS
  elif [[ "$scenario" == "reviewed-with-action-items" || "$scenario" == "reviewed-with-action-items-no-original-author" || "$scenario" == "reviewed-with-action-items-unrelated-author-mention" ]]; then
    cat <<'COMMENTS'
Verdict: request-changes

- src/app.ts:7 -- missing regression test.

<!-- engineer-reviewed: deadbeef verdict: request-changes -->
Verdict: request-changes

Security findings: none.
Performance findings:
- [missing-timeout] src/app.ts:12 -- outbound call has no timeout.

<!-- evaluator-reviewed: deadbeef verdict: request-changes -->
COMMENTS
  elif [[ "$scenario" == "reviewed-debate" ]]; then
    cat <<'COMMENTS'
Verdict: request-changes

- src/app.ts:7 -- missing regression test.

<!-- engineer-reviewed: deadbeef verdict: request-changes -->
Verdict: approve

Security findings: none.
Performance findings: none.

<!-- evaluator-reviewed: deadbeef verdict: approve -->
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

<!-- engineer-reviewed: deadbeef verdict: request-changes -->
Verdict: request-changes

Security findings: none.
Performance findings:
- [missing-timeout] src/app.ts:12 -- outbound call still has no timeout.

<!-- evaluator-reviewed: deadbeef verdict: request-changes -->
COMMENTS
  elif [[ "$scenario" == "debate-unresolved" ]]; then
    # A debate sentinel with no CEO resolution: the sweep must WAIT, not
    # treat the PR as converged. The quoted resolution template in the prose
    # must not parse as a real ceo-resolved sentinel.
    cat <<'COMMENTS'
<!-- multica-pr-review-issue: 11111111-1111-1111-1111-000000000001 -->
Verdict: request-changes

- src/app.ts:7 -- missing regression test.

<!-- engineer-reviewed: deadbeef verdict: request-changes -->
Verdict: approve

<!-- evaluator-reviewed: deadbeef verdict: approve -->
Reviewers disagree — escalating to the CEO for adjudication. The debate stays open until the CEO posts the resolution sentinel on this PR: `<!-- ceo-resolved: deadbeef verdict: <approve|request-changes|block> -->`.

<!-- debate: deadbeef -->
COMMENTS
  elif [[ "$scenario" == "debate-ceo-resolved-approve" ]]; then
    cat <<'COMMENTS'
<!-- multica-pr-review-issue: 11111111-1111-1111-1111-000000000001 -->
Verdict: request-changes

- src/app.ts:7 -- missing regression test.

<!-- engineer-reviewed: deadbeef verdict: request-changes -->
Verdict: approve

<!-- evaluator-reviewed: deadbeef verdict: approve -->
Reviewers disagree — escalating to the CEO for adjudication.

<!-- debate: deadbeef -->
Adjudication: the peer-lane finding is a test-coverage nit; approving.

<!-- ceo-resolved: deadbeef verdict: approve -->
COMMENTS
  elif [[ "$scenario" == "debate-ceo-resolved-request-changes" ]]; then
    cat <<'COMMENTS'
<!-- multica-pr-review-issue: 11111111-1111-1111-1111-000000000001 -->
Verdict: request-changes

- src/app.ts:7 -- missing regression test.

<!-- engineer-reviewed: deadbeef verdict: request-changes -->
Verdict: approve

<!-- evaluator-reviewed: deadbeef verdict: approve -->
Reviewers disagree — escalating to the CEO for adjudication.

<!-- debate: deadbeef -->
Adjudication: the regression test is required; I have dispatched rework.

<!-- ceo-resolved: deadbeef verdict: request-changes -->
COMMENTS
  elif [[ "$scenario" == "evaluator-author-one-engineer-review" ]]; then
    cat <<'COMMENTS'
<!-- multica-pr-review-issue: 11111111-1111-1111-1111-000000000001 -->
Verdict: approve

What I checked:
- src/app.ts:1 -- change is covered.

<!-- engineer-reviewed: deadbeef verdict: approve -->
COMMENTS
  elif [[ "$scenario" == "evaluator-author-two-engineer-reviews" ]]; then
    cat <<'COMMENTS'
<!-- multica-pr-review-issue: 11111111-1111-1111-1111-000000000001 -->
Verdict: request-changes

- src/app.ts:7 -- missing regression test.

<!-- engineer-reviewed: deadbeef verdict: request-changes -->
Verdict: request-changes

- src/app.ts:12 -- adversarial input path unguarded.

<!-- engineer-reviewed: deadbeef verdict: request-changes -->
COMMENTS
  elif [[ "$scenario" == "reviewed-with-prose-mention-not-counted" ]]; then
    # Prose that quotes prior sentinels must not inflate the iteration
    # counter — only real `<!-- consensus: ... -->` sentinels count. One real
    # prior round + prose fakes = advisory iteration 2 of 3, NOT cap-reached.
    cat <<'COMMENTS'
Earlier we noted the consensus: feedfeedfeedfeedfeedfeedfeedfeedfeedfeed verdict: request-changes call was wrong.

A reviewer quoted: "the marker `consensus: cafebabecafebabecafebabecafebabecafebabe verdict: block` got mangled in transit"

The actual prior sentinel:

<!-- consensus: 1111111111111111111111111111111111111111 verdict: request-changes -->

Now the new round:

Verdict: request-changes

- src/app.ts:7 -- still missing regression test.

<!-- engineer-reviewed: deadbeef verdict: request-changes -->
Verdict: request-changes

Security findings: none.

<!-- evaluator-reviewed: deadbeef verdict: request-changes -->
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
    printf '[{"content":"<!-- multica-review-requested: deadbeef agent: engineer-a -->"}]\n'
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
    PR_SWEEP_GH_VIEW_FAIL="${PR_SWEEP_GH_VIEW_FAIL:-0}" \
    PR_SWEEP_MULTICA_FAIL="${PR_SWEEP_MULTICA_FAIL:-0}" \
    PR_SWEEP_EXISTING_ORIGIN_COMMENT="${PR_SWEEP_EXISTING_ORIGIN_COMMENT:-0}" \
    LC_ALL=C \
    LANG=C \
    PATH="$tmp/bin:$PATH" \
    GH_OWNER="stone16" \
    ENGINEER_A_AGENT="Engineer-A" \
    ENGINEER_B_AGENT="Engineer-B" \
    EVALUATOR_AGENT="Evaluator" \
    CEO_AGENT="CEO" \
    CEO_MENTION="$CEO_MENTION_LINK" \
    ENGINEER_A_MENTION="$ENGINEER_A_MENTION_LINK" \
    ENGINEER_B_MENTION="$ENGINEER_B_MENTION_LINK" \
    EVALUATOR_MENTION="$EVALUATOR_MENTION_LINK" \
    PR_SWEEP_IGNORE="${PR_SWEEP_IGNORE_OVERRIDE:-}" \
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

test_unreviewed_pr_creates_one_review_issue_for_peer_engineer() {
  local tmp
  tmp="$(run_sweep_with_stubs unreviewed)"

  assert_file_count "$tmp/captures" 1
  assert_comment_count "$tmp/captures" 1
  assert_update_count "$tmp/captures" 1
  assert_pr_comment_count "$tmp/captures" 1
  assert_contains "$tmp/captures/issue-1.args" "--assignee Engineer-A"
  assert_contains "$tmp/captures/issue-update-1.args" "--assignee Engineer-A"
  assert_contains "$tmp/captures/issue-1.args" "--title PR review - stone16/sample-repo#12"
  assert_contains "$tmp/captures/issue-1.description.md" "[stone16/sample-repo#12](https://github.com/stone16/sample-repo/pull/12) @ deadbeef"
  assert_contains "$tmp/captures/issue-1.description.md" "This is the single Multica thread for this PR review."
  assert_contains "$tmp/captures/issue-comment-1.md" "Engineer-A review is requested for [stone16/sample-repo#12](https://github.com/stone16/sample-repo/pull/12) @ deadbeef."
  assert_contains "$tmp/captures/issue-comment-1.md" "the Engineer peer lane"
  assert_contains "$tmp/captures/issue-comment-1.md" "<!-- engineer-reviewed: <head-sha> verdict: <approve|request-changes|block> -->"
  assert_contains "$tmp/captures/issue-1.description.md" "Two review lanes are required on every PR; this is not a rotation."
  assert_contains "$tmp/captures/issue-1.description.md" "The Engineer peer lane"
  assert_contains "$tmp/captures/issue-1.description.md" "The Evaluator adversarial lane owns security, performance, dependency-risk, and adversarial-input review."
  assert_contains "$tmp/captures/issue-1.description.md" "Documentation-only PRs receive the same dual review"
  assert_contains "$tmp/captures/issue-1.description.md" "Minimum review bar is identical for both lanes:"
  assert_contains "$tmp/captures/issue-1.description.md" "Every non-approve outcome — agreed request-changes, agreed block, or lane disagreement — is escalated to the CEO in this issue; the sweep never @-mentions the PR's author."
  assert_contains "$tmp/captures/issue-1.description.md" "multica repo checkout https://github.com/<owner>/<repo>.git --ref <head-sha>"
  assert_contains "$tmp/captures/issue-1.description.md" "If \`multica repo checkout\` fails because the SHA is unreachable"
  assert_contains "$tmp/captures/issue-1.description.md" "A sentinel must always reflect a review actually conducted on the SHA it tags"
  assert_contains "$tmp/captures/issue-1.description.md" "Use the PR link above in your PR comment and in this Multica issue summary"
  assert_contains "$tmp/captures/issue-1.description.md" "<!-- <engineer|evaluator>-reviewed: <head-sha> verdict: <approve|request-changes|block> -->"
  assert_contains "$tmp/captures/issue-comment-1.md" "<!-- multica-review-requested: deadbeef agent: engineer-a -->"
  assert_contains "$tmp/captures/pr-comment-1.md" "<!-- multica-pr-review-issue: 11111111-1111-1111-1111-000000000001 -->"

  # Race-condition guard: the headRefOid pin must appear BEFORE the worktree
  # checkout, otherwise an agent can review a stale SHA and post a sentinel
  # tagged with a newer SHA it never actually reviewed.
  assert_line_before "$tmp/captures/issue-1.description.md" \
    "gh pr view <num> --repo <owner/repo> --json headRefOid --jq .headRefOid" \
    "multica repo checkout https://github.com/<owner>/<repo>.git --ref <head-sha>"
}

test_peer_lane_picks_engineer_b_when_author_is_engineer_a() {
  local tmp
  tmp="$(run_sweep_with_stubs unreviewed-author-engineer-a)"

  assert_file_count "$tmp/captures" 1
  assert_comment_count "$tmp/captures" 1
  assert_contains "$tmp/captures/issue-1.args" "--assignee Engineer-B"
  assert_contains "$tmp/captures/issue-update-1.args" "--assignee Engineer-B"
  assert_contains "$tmp/captures/issue-comment-1.md" "Engineer-B review is requested for [stone16/sample-repo#12](https://github.com/stone16/sample-repo/pull/12) @ deadbeef."
  assert_contains "$tmp/captures/issue-comment-1.md" "<!-- multica-review-requested: deadbeef agent: engineer-b -->"
  assert_contains "$tmp/captures/issue-comment-1.md" "<!-- engineer-reviewed: <head-sha> verdict: <approve|request-changes|block> -->"
}

test_peer_lane_picks_engineer_a_when_author_is_engineer_b() {
  local tmp
  tmp="$(run_sweep_with_stubs unreviewed-author-engineer-b)"

  assert_contains "$tmp/captures/issue-1.args" "--assignee Engineer-A"
  assert_contains "$tmp/captures/issue-comment-1.md" "Engineer-A review is requested for [stone16/sample-repo#12](https://github.com/stone16/sample-repo/pull/12) @ deadbeef."
  assert_contains "$tmp/captures/issue-comment-1.md" "<!-- multica-review-requested: deadbeef agent: engineer-a -->"
}

test_existing_review_issue_marker_prevents_duplicate_review_request() {
  local tmp
  tmp="$(run_sweep_with_stubs unreviewed-review-issue-exists)"

  assert_file_count "$tmp/captures" 0
  assert_comment_count "$tmp/captures" 0
  assert_update_count "$tmp/captures" 1
  assert_pr_comment_count "$tmp/captures" 0
  assert_contains "$tmp/captures/issue-update-1.args" "11111111-1111-1111-1111-000000000001"
  assert_contains "$tmp/captures/issue-update-1.args" "--assignee Engineer-A"
  assert_contains "$tmp/stderr.log" "review-request=exists 11111111-1111-1111-1111-000000000001 stone16/sample-repo#12@deadbeef"
}

test_after_engineer_review_routes_evaluator_in_same_review_issue() {
  local tmp
  tmp="$(run_sweep_with_stubs reviewed-engineer-only-review-issue-exists)"

  assert_file_count "$tmp/captures" 0
  assert_comment_count "$tmp/captures" 1
  assert_update_count "$tmp/captures" 1
  assert_pr_comment_count "$tmp/captures" 0
  assert_contains "$tmp/captures/issue-update-1.args" "11111111-1111-1111-1111-000000000001"
  assert_contains "$tmp/captures/issue-update-1.args" "--assignee Evaluator"
  assert_contains "$tmp/captures/issue-comment-1.md" "Evaluator review is requested for [stone16/sample-repo#12](https://github.com/stone16/sample-repo/pull/12) @ deadbeef."
  assert_contains "$tmp/captures/issue-comment-1.md" "the Evaluator adversarial lane"
  assert_contains "$tmp/captures/issue-comment-1.md" "<!-- evaluator-reviewed: <head-sha> verdict: <approve|request-changes|block> -->"
  assert_contains "$tmp/captures/issue-comment-1.md" "<!-- multica-review-requested: deadbeef agent: evaluator -->"
}

# Leader-only routing: EVERY non-approve reconciled outcome mentions ONLY the
# CEO. The sweep never @-mentions the PR's author — the CEO dispatches rework.
test_nonapprove_consensus_escalates_to_ceo_not_author() {
  local tmp
  tmp="$(run_sweep_with_stubs reviewed-with-action-items)"

  assert_file_count "$tmp/captures" 1
  assert_comment_count "$tmp/captures" 1
  assert_update_count "$tmp/captures" 1
  assert_pr_comment_count "$tmp/captures" 2
  assert_contains "$tmp/captures/issue-comment-1.args" "11111111-1111-1111-1111-000000000001"
  assert_contains "$tmp/captures/issue-update-1.args" "--assignee CEO"
  assert_contains "$tmp/captures/issue-comment-1.md" "$CEO_MENTION_LINK"
  # The author identity appears ONLY as the backticked informational line —
  # never as a live mention (leader-only routing).
  assert_contains "$tmp/captures/issue-comment-1.md" '- Original author: `'"$ENGINEER_A_MENTION_LINK"'`'
  assert_not_contains "$tmp/captures/issue-comment-1.md" "$ENGINEER_B_MENTION_LINK"
  assert_not_contains "$tmp/captures/issue-comment-1.md" "$EVALUATOR_MENTION_LINK"
  assert_contains "$tmp/captures/issue-comment-1.md" "dispatch rework to the PR's author agent"
  assert_contains "$tmp/captures/issue-comment-1.md" "- PR: https://github.com/stone16/sample-repo/pull/12"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Head commit: deadbeef"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Final verdict: consensus: request-changes"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Engineer verdict (peer lane): request-changes"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Evaluator verdict (adversarial lane): request-changes"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Rework iteration 1 of 3 for this PR (advisory"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Action: ceo-followup"
  assert_not_contains "$tmp/captures/issue-comment-1.md" "author-iteration"
  assert_contains "$tmp/captures/issue-comment-1.md" "missing regression test."
  assert_contains "$tmp/captures/issue-comment-1.md" "outbound call has no timeout."
  assert_contains "$tmp/captures/issue-comment-1.md" "## Discussion Protocol"
  assert_not_contains "$tmp/captures/issue-comment-1.md" "## Rework Protocol"
  assert_contains "$tmp/captures/issue-comment-1.md" 'Reply to each reviewer finding in this issue with one of: `will-fix`, `already-fixed`, `wont-fix`, or `needs-discussion`'
  assert_not_contains "$tmp/captures/issue-comment-1.md" "engineer-reviewed:"
  assert_not_contains "$tmp/captures/issue-comment-1.md" "evaluator-reviewed:"
  assert_contains "$tmp/captures/issue-comment-1.md" "<!-- multica-review-dispatched: deadbeef -->"
  assert_contains "$tmp/captures/pr-comment-1.md" "<!-- multica-pr-review-issue: 11111111-1111-1111-1111-000000000001 -->"
  assert_contains "$tmp/captures/pr-comment.md" "<!-- consensus: deadbeef verdict: request-changes -->"
}

test_iteration_cap_is_advisory_and_flagged_to_ceo() {
  local tmp
  tmp="$(run_sweep_with_stubs reviewed-with-action-items-iter-cap)"

  assert_file_count "$tmp/captures" 1
  assert_comment_count "$tmp/captures" 1
  assert_update_count "$tmp/captures" 1
  assert_contains "$tmp/captures/issue-comment-1.md" "$CEO_MENTION_LINK"
  assert_contains "$tmp/captures/issue-comment-1.md" '- Original author: `'"$ENGINEER_A_MENTION_LINK"'`'
  assert_not_contains "$tmp/captures/issue-comment-1.md" "$ENGINEER_B_MENTION_LINK"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Rework iterations so far: 3 (cap: 3 — reached; advisory: escalate to the human instead of dispatching rework)"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Action: ceo-followup"
  assert_contains "$tmp/captures/issue-comment-1.md" "## Discussion Protocol"
  assert_contains "$tmp/captures/issue-update-1.args" "--assignee CEO"
  assert_contains "$tmp/captures/pr-comment.md" "<!-- consensus: deadbeef verdict: request-changes -->"
}

test_missing_original_author_escalates_to_ceo() {
  local tmp
  tmp="$(run_sweep_with_stubs reviewed-with-action-items-no-original-author)"

  assert_file_count "$tmp/captures" 1
  assert_comment_count "$tmp/captures" 1
  assert_update_count "$tmp/captures" 1
  assert_pr_comment_count "$tmp/captures" 2
  assert_contains "$tmp/captures/issue-comment-1.md" "$CEO_MENTION_LINK"
  assert_contains "$tmp/captures/issue-comment-1.md" "no \`Original author:"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Original author: unknown (human-authored or preamble unparseable) — no agent rework target; treat as human-owned"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Action: ceo-followup"
  assert_contains "$tmp/captures/issue-comment-1.md" "## Discussion Protocol"
  assert_contains "$tmp/captures/issue-comment-1.md" 'Reply to each reviewer finding in this issue with one of: `will-fix`, `already-fixed`, `wont-fix`, or `needs-discussion`.'
  assert_contains "$tmp/captures/issue-comment-1.md" "Keep the thread unresolved until the CEO and the reviewer agree on the outcome."
  assert_contains "$tmp/captures/issue-comment-1.md" "End with a summary comment before marking the thread resolved."
  assert_contains "$tmp/captures/issue-update-1.args" "--assignee CEO"
  assert_contains "$tmp/captures/pr-comment.md" "<!-- consensus: deadbeef verdict: request-changes -->"
}

test_unrelated_agent_mentions_do_not_route_rework() {
  local tmp
  tmp="$(run_sweep_with_stubs reviewed-with-action-items-unrelated-author-mention)"

  assert_file_count "$tmp/captures" 1
  assert_comment_count "$tmp/captures" 1
  assert_update_count "$tmp/captures" 1
  assert_contains "$tmp/captures/issue-comment-1.md" "$CEO_MENTION_LINK"
  assert_not_contains "$tmp/captures/issue-comment-1.md" "$ENGINEER_B_MENTION_LINK"
  # The thank-you mention in the PR body is not an `Original author:` line —
  # the outcome comment must report the author as unknown.
  assert_contains "$tmp/captures/issue-comment-1.md" "- Original author: unknown (human-authored or preamble unparseable) — no agent rework target; treat as human-owned"
  assert_not_contains "$tmp/captures/issue-comment-1.md" "- Action: author-iteration"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Action: ceo-followup"
  assert_contains "$tmp/captures/pr-comment.md" "<!-- consensus: deadbeef verdict: request-changes -->"
}

test_prior_prose_sentinels_do_not_inflate_iteration_count() {
  local tmp
  tmp="$(run_sweep_with_stubs reviewed-with-prose-mention-not-counted)"

  assert_file_count "$tmp/captures" 1
  assert_comment_count "$tmp/captures" 1
  assert_update_count "$tmp/captures" 1
  assert_contains "$tmp/captures/issue-comment-1.md" "- Action: ceo-followup"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Rework iteration 2 of 3 for this PR (advisory"
  assert_not_contains "$tmp/captures/issue-comment-1.md" "cap: 3 — reached"
  assert_contains "$tmp/captures/issue-comment-1.md" "$CEO_MENTION_LINK"
  assert_contains "$tmp/captures/issue-comment-1.md" '- Original author: `'"$ENGINEER_A_MENTION_LINK"'`'
  assert_not_contains "$tmp/captures/issue-comment-1.md" "$ENGINEER_B_MENTION_LINK"
}

test_approve_consensus_closes_existing_review_issue_without_ceo() {
  local tmp
  tmp="$(run_sweep_with_stubs reviewed-approve-approve-review-issue-exists)"

  assert_file_count "$tmp/captures" 0
  assert_comment_count "$tmp/captures" 0
  assert_update_count "$tmp/captures" 1
  assert_contains "$tmp/captures/issue-update-1.args" "--status done"
  assert_not_contains "$tmp/captures/issue-update-1.args" "--assignee"
  assert_contains "$tmp/captures/pr-comment.md" "<!-- consensus: deadbeef verdict: approve -->"
}

test_debate_routes_to_ceo_in_pr_review_issue() {
  local tmp
  tmp="$(run_sweep_with_stubs reviewed-debate)"

  assert_file_count "$tmp/captures" 1
  assert_comment_count "$tmp/captures" 1
  assert_update_count "$tmp/captures" 1
  assert_contains "$tmp/captures/issue-comment-1.md" "$CEO_MENTION_LINK"
  assert_not_contains "$tmp/captures/issue-comment-1.md" "$ENGINEER_A_MENTION_LINK"
  assert_not_contains "$tmp/captures/issue-comment-1.md" "$ENGINEER_B_MENTION_LINK"
  assert_contains "$tmp/captures/issue-update-1.args" "--assignee CEO"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Action: ceo-debate"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Final verdict: debate"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Engineer verdict (peer lane): request-changes"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Evaluator verdict (adversarial lane): approve"
  assert_not_contains "$tmp/captures/issue-comment-1.md" "engineer-reviewed:"
  assert_not_contains "$tmp/captures/issue-comment-1.md" "evaluator-reviewed:"
  assert_contains "$tmp/captures/pr-comment.md" "- Engineer (peer lane): request-changes"
  assert_contains "$tmp/captures/pr-comment.md" "- Evaluator (adversarial lane): approve"
  # The debate comment names the exact resolution sentinel the CEO must post.
  assert_contains "$tmp/captures/pr-comment.md" 'ceo-resolved: deadbeef verdict: <approve|request-changes|block>'
  assert_contains "$tmp/captures/pr-comment.md" "<!-- debate: deadbeef -->"
}

# A debate sentinel is NOT terminal. Without a CEO resolution sentinel the
# sweep waits — it must neither re-dispatch nor treat the PR as converged.
test_debate_without_resolution_waits_for_ceo() {
  local tmp
  tmp="$(run_sweep_with_stubs debate-unresolved)"

  assert_status "$tmp" 0
  assert_file_count "$tmp/captures" 0
  assert_comment_count "$tmp/captures" 0
  assert_pr_comment_count "$tmp/captures" 0
  assert_update_count "$tmp/captures" 0
  assert_contains "$tmp/stderr.log" "waiting for CEO adjudication"
}

# debate + ceo-resolved for the SAME sha with verdict approve → the sweep
# writes the final consensus sentinel with the resolved verdict and marks the
# review issue done.
test_debate_with_ceo_resolution_approve_converges_and_closes_issue() {
  local tmp
  tmp="$(run_sweep_with_stubs debate-ceo-resolved-approve)"

  assert_file_count "$tmp/captures" 0
  assert_comment_count "$tmp/captures" 0
  assert_pr_comment_count "$tmp/captures" 1
  assert_contains "$tmp/captures/pr-comment.md" "<!-- consensus: deadbeef verdict: approve -->"
  assert_update_count "$tmp/captures" 1
  assert_contains "$tmp/captures/issue-update-1.args" "11111111-1111-1111-1111-000000000001"
  assert_contains "$tmp/captures/issue-update-1.args" "--status done"
  assert_contains "$tmp/stderr.log" "[resolved] stone16/sample-repo#12@deadbeef (debate → approve)"
}

# debate + ceo-resolved non-approve → the CEO already owns rework from the
# adjudication: the sweep records the consensus sentinel with the resolved
# verdict and stops — no new outcome comment, no issue reassignment.
test_debate_with_ceo_resolution_nonapprove_records_without_new_outcome() {
  local tmp
  tmp="$(run_sweep_with_stubs debate-ceo-resolved-request-changes)"

  assert_file_count "$tmp/captures" 0
  assert_comment_count "$tmp/captures" 0
  assert_update_count "$tmp/captures" 0
  assert_pr_comment_count "$tmp/captures" 1
  assert_contains "$tmp/captures/pr-comment.md" "CEO adjudication recorded: request-changes — debate resolved."
  assert_contains "$tmp/captures/pr-comment.md" "<!-- consensus: deadbeef verdict: request-changes -->"
  assert_contains "$tmp/stderr.log" "[resolved] stone16/sample-repo#12@deadbeef (debate → request-changes)"
}

# A failed gh read must never look like empty data: the PR is skipped for
# this sweep with zero writes and the failure is counted.
test_pr_fetch_failure_skips_pr_without_decisions() {
  local tmp
  tmp="$(PR_SWEEP_GH_VIEW_FAIL=1 run_sweep_with_stubs unreviewed)"

  assert_status "$tmp" 0
  assert_file_count "$tmp/captures" 0
  assert_comment_count "$tmp/captures" 0
  assert_pr_comment_count "$tmp/captures" 0
  assert_update_count "$tmp/captures" 0
  assert_contains "$tmp/stderr.log" "fetch failed"
  assert_contains "$tmp/stderr.log" "skipping this sweep"
  assert_contains "$tmp/stderr.log" "prs_fetch_failed=1"
}

# Lane guard: when the Evaluator authored the PR, the adversarial lane must
# not self-review. The peer lane goes to Engineer-A first.
test_evaluator_authored_pr_dispatches_engineer_a_peer_first() {
  local tmp
  tmp="$(run_sweep_with_stubs unreviewed-author-evaluator)"

  assert_file_count "$tmp/captures" 1
  assert_comment_count "$tmp/captures" 1
  assert_contains "$tmp/captures/issue-1.args" "--assignee Engineer-A"
  assert_not_contains "$tmp/captures/issue-1.args" "--assignee Evaluator"
  assert_contains "$tmp/captures/issue-comment-1.md" "<!-- multica-review-requested: deadbeef agent: engineer-a -->"
  assert_contains "$tmp/captures/issue-comment-1.md" "<!-- engineer-reviewed: <head-sha> verdict: <approve|request-changes|block> -->"
  assert_contains "$tmp/stderr.log" "[need-engineer-first] stone16/sample-repo#12@deadbeef (evaluator-authored; peer=Engineer-A)"
}

# Lane guard: after the first engineer review on an Evaluator-authored PR,
# the adversarial checklist is dispatched to Engineer-B, who still writes the
# engineer-reviewed sentinel (never evaluator-reviewed).
test_evaluator_authored_pr_dispatches_engineer_b_for_adversarial_lane() {
  local tmp
  tmp="$(run_sweep_with_stubs evaluator-author-one-engineer-review)"

  assert_file_count "$tmp/captures" 0
  assert_comment_count "$tmp/captures" 1
  assert_update_count "$tmp/captures" 1
  assert_contains "$tmp/captures/issue-update-1.args" "--assignee Engineer-B"
  assert_contains "$tmp/captures/issue-comment-1.md" "Engineer-B review is requested"
  assert_contains "$tmp/captures/issue-comment-1.md" "the adversarial lane on an Evaluator-authored PR"
  assert_contains "$tmp/captures/issue-comment-1.md" 'write the `engineer-reviewed` sentinel (never `evaluator-reviewed`)'
  assert_contains "$tmp/captures/issue-comment-1.md" "<!-- engineer-reviewed: <head-sha> verdict: <approve|request-changes|block> -->"
  assert_not_contains "$tmp/captures/issue-comment-1.md" "<!-- evaluator-reviewed: <head-sha>"
  assert_contains "$tmp/captures/issue-comment-1.md" "<!-- multica-review-requested: deadbeef agent: engineer-b -->"
}

# Lane guard consensus: two engineer-reviewed sentinels from two distinct
# review comments are the two lanes for an Evaluator-authored PR (first =
# peer, second = adversarial), with lane attribution in the outcome comment.
test_evaluator_authored_pr_two_engineer_sentinels_reach_consensus() {
  local tmp
  tmp="$(run_sweep_with_stubs evaluator-author-two-engineer-reviews)"

  assert_file_count "$tmp/captures" 0
  assert_comment_count "$tmp/captures" 1
  assert_update_count "$tmp/captures" 1
  assert_pr_comment_count "$tmp/captures" 1
  assert_contains "$tmp/captures/issue-comment-1.md" "$CEO_MENTION_LINK"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Final verdict: consensus: request-changes"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Peer lane verdict (Engineer): request-changes"
  assert_contains "$tmp/captures/issue-comment-1.md" "- Adversarial lane verdict (Engineer — Evaluator-authored PR): request-changes"
  assert_contains "$tmp/captures/issue-comment-1.md" '- Original author: `'"$EVALUATOR_MENTION_LINK"'`'
  assert_contains "$tmp/captures/issue-comment-1.md" "## Peer Lane Review (Engineer)"
  assert_contains "$tmp/captures/issue-comment-1.md" "## Adversarial Lane Review (Engineer — Evaluator-authored PR)"
  assert_contains "$tmp/captures/issue-comment-1.md" "missing regression test."
  assert_contains "$tmp/captures/issue-comment-1.md" "adversarial input path unguarded."
  assert_contains "$tmp/captures/issue-update-1.args" "--assignee CEO"
  assert_contains "$tmp/captures/pr-comment.md" "<!-- consensus: deadbeef verdict: request-changes -->"
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
  [[ ! -f "$tmp/captures/pr-comment.md" ]] || fail "final PR sentinel was written even though outcome delegation failed"
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

test_env_ignore_list_skips_repo() {
  local tmp
  tmp="$(PR_SWEEP_IGNORE_OVERRIDE=$'# personal sandbox\nsample-repo' run_sweep_with_stubs unreviewed)"

  assert_status "$tmp" 0
  assert_file_count "$tmp/captures" 0
  assert_comment_count "$tmp/captures" 0
  assert_pr_comment_count "$tmp/captures" 0
  assert_contains "$tmp/stderr.log" "[skip] sample-repo (ignore list)"
}

test_env_ignore_list_nonmatching_repo_still_swept() {
  local tmp
  tmp="$(PR_SWEEP_IGNORE_OVERRIDE="other-repo" run_sweep_with_stubs unreviewed)"

  assert_file_count "$tmp/captures" 1
  assert_contains "$tmp/captures/issue-1.args" "--assignee Engineer-A"
}

test_unreviewed_pr_creates_one_review_issue_for_peer_engineer
test_peer_lane_picks_engineer_b_when_author_is_engineer_a
test_peer_lane_picks_engineer_a_when_author_is_engineer_b
test_existing_review_issue_marker_prevents_duplicate_review_request
test_after_engineer_review_routes_evaluator_in_same_review_issue
test_nonapprove_consensus_escalates_to_ceo_not_author
test_iteration_cap_is_advisory_and_flagged_to_ceo
test_missing_original_author_escalates_to_ceo
test_unrelated_agent_mentions_do_not_route_rework
test_prior_prose_sentinels_do_not_inflate_iteration_count
test_approve_consensus_closes_existing_review_issue_without_ceo
test_debate_routes_to_ceo_in_pr_review_issue
test_debate_without_resolution_waits_for_ceo
test_debate_with_ceo_resolution_approve_converges_and_closes_issue
test_debate_with_ceo_resolution_nonapprove_records_without_new_outcome
test_pr_fetch_failure_skips_pr_without_decisions
test_evaluator_authored_pr_dispatches_engineer_a_peer_first
test_evaluator_authored_pr_dispatches_engineer_b_for_adversarial_lane
test_evaluator_authored_pr_two_engineer_sentinels_reach_consensus
test_existing_review_outcome_prevents_duplicate_when_final_comment_fails
test_multica_dispatch_failure_does_not_abort_sweep
test_review_outcome_failure_does_not_write_final_sentinel
test_existing_review_outcome_allows_final_comment_without_duplicate
test_env_ignore_list_skips_repo
test_env_ignore_list_nonmatching_repo_still_swept
printf 'PASS: pr-sweep PR issue routing tests\n'
