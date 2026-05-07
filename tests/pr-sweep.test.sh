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

assert_file_count() {
  local dir="$1"
  local expected="$2"
  local actual
  actual=$(find "$dir" -type f -name 'issue-*.description.md' | wc -l | tr -d ' ')
  [[ "$actual" == "$expected" ]] || fail "expected $expected issue descriptions, got $actual"
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
  if [[ "$scenario" == "reviewed-with-action-items" || "$scenario" == "reviewed-with-action-items-comment-fails" ]]; then
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
  fi
  exit 0
fi

if [[ "$1 $2" == "pr comment" ]]; then
  if [[ "${PR_SWEEP_PR_COMMENT_FAIL:-0}" == "1" ]]; then
    printf 'simulated pr comment failure\n' >&2
    exit 1
  fi
  cat >"$PR_SWEEP_CAPTURE_DIR/pr-comment.md"
  exit 0
fi

printf 'unexpected gh invocation: %s\n' "$*" >&2
exit 64
GH

  cat >"$tmp/bin/multica" <<'MULTICA'
#!/usr/bin/env bash
set -euo pipefail

[[ "$1 $2" == "issue create" ]] || {
  if [[ "$1 $2" == "issue list" ]]; then
    if [[ "${PR_SWEEP_EXISTING_DELEGATION:-0}" == "1" ]]; then
      printf '[{"title":"PR review delegation needed — stone16/sample-repo#12@deadbeef"}]\n'
    else
      printf '[]\n'
    fi
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
printf '{"id":"issue-%s"}\n' "$idx"
MULTICA

  chmod +x "$tmp/bin/gh" "$tmp/bin/multica"

  set +e
  PR_SWEEP_TEST_SCENARIO="$scenario" \
    PR_SWEEP_CAPTURE_DIR="$tmp/captures" \
    PR_SWEEP_PR_COMMENT_FAIL="${PR_SWEEP_PR_COMMENT_FAIL:-0}" \
    PR_SWEEP_MULTICA_FAIL="${PR_SWEEP_MULTICA_FAIL:-0}" \
    PR_SWEEP_EXISTING_DELEGATION="${PR_SWEEP_EXISTING_DELEGATION:-0}" \
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

test_dispatch_prompt_includes_clickable_pr_links() {
  local tmp
  tmp="$(run_sweep_with_stubs unreviewed)"

  assert_file_count "$tmp/captures" 2
  assert_contains "$tmp/captures/issue-1.description.md" "[stone16/sample-repo#12](https://github.com/stone16/sample-repo/pull/12) @ deadbeef"
  assert_contains "$tmp/captures/issue-1.description.md" "Both reviewers are required on every non-docs production-code PR; this is not a rotation."
  assert_contains "$tmp/captures/issue-1.description.md" "Minimum review bar is identical for both reviewers:"
  assert_contains "$tmp/captures/issue-1.description.md" "Use the PR link above in your PR comment and in this Multica issue summary"
  assert_contains "$tmp/captures/issue-2.description.md" "[stone16/sample-repo#12](https://github.com/stone16/sample-repo/pull/12) @ deadbeef"
}

test_cto_delegation_issue_created_for_actionable_consensus() {
  local tmp
  tmp="$(run_sweep_with_stubs reviewed-with-action-items)"

  assert_file_count "$tmp/captures" 1
  assert_contains "$tmp/captures/issue-1.args" "--assignee Stometa"
  assert_contains "$tmp/captures/issue-1.args" "PR review delegation needed — stone16/sample-repo#12@deadbeef"
  assert_contains "$tmp/captures/issue-1.description.md" "CTO delegation needed for [stone16/sample-repo#12](https://github.com/stone16/sample-repo/pull/12)."
  assert_contains "$tmp/captures/issue-1.description.md" "- PR: [stone16/sample-repo#12](https://github.com/stone16/sample-repo/pull/12)"
  assert_contains "$tmp/captures/issue-1.description.md" "- Head commit: deadbeef"
  assert_contains "$tmp/captures/issue-1.description.md" "- Reviewer verdicts: Hao=request-changes, Dustin=request-changes"
}

test_no_cto_delegation_for_approve_consensus() {
  local tmp
  tmp="$(run_sweep_with_stubs reviewed-approve-approve)"

  assert_file_count "$tmp/captures" 0
  assert_contains "$tmp/captures/pr-comment.md" "<!-- consensus: deadbeef verdict: approve -->"
}

test_existing_delegation_prevents_duplicate_when_final_comment_fails() {
  local tmp
  tmp="$(PR_SWEEP_PR_COMMENT_FAIL=1 run_sweep_with_stubs reviewed-with-action-items-comment-fails)"

  assert_status "$tmp" 0
  assert_file_count "$tmp/captures" 1
  [[ ! -f "$tmp/captures/pr-comment.md" ]] || fail "final PR sentinel unexpectedly succeeded"
  assert_contains "$tmp/stderr.log" "[warn] post_pr_comment failed for stone16/sample-repo#12"
}

test_multica_dispatch_failure_does_not_abort_sweep() {
  local tmp
  tmp="$(PR_SWEEP_MULTICA_FAIL=1 run_sweep_with_stubs unreviewed)"

  assert_status "$tmp" 0
  assert_file_count "$tmp/captures" 0
  assert_contains "$tmp/stderr.log" "[warn] dispatch_agent failed for Hao"
  assert_contains "$tmp/stderr.log" "[warn] dispatch_agent failed for Dustin"
}

test_cto_delegation_failure_does_not_abort_sweep() {
  local tmp
  tmp="$(PR_SWEEP_MULTICA_FAIL=1 run_sweep_with_stubs reviewed-with-action-items)"

  assert_status "$tmp" 0
  assert_file_count "$tmp/captures" 0
  [[ ! -f "$tmp/captures/pr-comment.md" ]] || fail "final PR sentinel was written even though CTO delegation failed"
  assert_contains "$tmp/stderr.log" "[warn] dispatch_cto_delegation failed for stone16/sample-repo#12"
}

test_existing_cto_delegation_allows_final_comment_without_duplicate() {
  local tmp
  tmp="$(PR_SWEEP_EXISTING_DELEGATION=1 PR_SWEEP_MULTICA_FAIL=1 run_sweep_with_stubs reviewed-with-action-items)"

  assert_status "$tmp" 0
  assert_file_count "$tmp/captures" 0
  assert_contains "$tmp/captures/pr-comment.md" "<!-- consensus: deadbeef verdict: request-changes -->"
  assert_contains "$tmp/stderr.log" "cto-delegation=exists stone16/sample-repo#12@deadbeef"
}

test_dispatch_prompt_includes_clickable_pr_links
test_cto_delegation_issue_created_for_actionable_consensus
test_no_cto_delegation_for_approve_consensus
test_existing_delegation_prevents_duplicate_when_final_comment_fails
test_multica_dispatch_failure_does_not_abort_sweep
test_cto_delegation_failure_does_not_abort_sweep
test_existing_cto_delegation_allows_final_comment_without_duplicate
printf 'PASS: pr-sweep prompt/delegation tests\n'
