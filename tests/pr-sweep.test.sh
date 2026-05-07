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

run_sweep_with_stubs() {
  local scenario="$1"
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
  if [[ "$scenario" == "reviewed-with-action-items" ]]; then
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
  fi
  exit 0
fi

if [[ "$1 $2" == "pr comment" ]]; then
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
  printf 'unexpected multica invocation: %s\n' "$*" >&2
  exit 64
}

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

  PR_SWEEP_TEST_SCENARIO="$scenario" \
  PR_SWEEP_CAPTURE_DIR="$tmp/captures" \
  LC_ALL=C \
  LANG=C \
  PATH="$tmp/bin:$PATH" \
  GH_OWNER="stone16" \
  HAO_AGENT="Hao" \
  DUSTIN_AGENT="Dustin" \
  CTO_AGENT="Stometa" \
  bash "$SCRIPT" >"$tmp/stdout.log" 2>"$tmp/stderr.log"

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
  assert_contains "$tmp/captures/issue-1.description.md" "CTO delegation needed for [stone16/sample-repo#12](https://github.com/stone16/sample-repo/pull/12)."
  assert_contains "$tmp/captures/issue-1.description.md" "- PR: [stone16/sample-repo#12](https://github.com/stone16/sample-repo/pull/12)"
  assert_contains "$tmp/captures/issue-1.description.md" "- Head commit: deadbeef"
  assert_contains "$tmp/captures/issue-1.description.md" "- Reviewer verdicts: Hao=request-changes, Dustin=request-changes"
}

test_dispatch_prompt_includes_clickable_pr_links
test_cto_delegation_issue_created_for_actionable_consensus
printf 'PASS: pr-sweep prompt/delegation tests\n'
