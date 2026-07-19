#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq -- "$needle" "$file" || fail "$file does not contain: $needle"
}

make_fixture() {
  local scenario="$1" tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/repo/scripts" "$tmp/repo/agents/ceo" "$tmp/bin" "$tmp/state"
  cp "$ROOT/scripts/sync-multica.sh" "$tmp/repo/scripts/"
  printf '%s\n' 'desired context' > "$tmp/repo/workspace-context.md"
  printf '%s\n' 'desired personality' > "$tmp/repo/agents/ceo/personality.md"
  printf '%s\n' 'desired skill' > "$tmp/repo/agents/ceo/skill.md"
  printf '%s' "$scenario" > "$tmp/state/scenario"

  cat > "$tmp/bin/multica" << 'STUB'
#!/usr/bin/env bash
set -euo pipefail

scenario="$(cat "$SYNC_TEST_STATE/scenario")"
printf '%s\n' "$*" >> "$SYNC_TEST_STATE/calls.log"

json_string_from_file() {
  python3 - "$1" << 'PY'
import json, sys
print(json.dumps(open(sys.argv[1], encoding="utf-8").read().rstrip("\n")))
PY
}

case "$1 $2" in
  "skill list")
    if [[ "$scenario" == "duplicate-skill" ]]; then
      printf '[{"id":"skill-one","name":"CEO Skill"},{"id":"skill-two","name":"CEO Skill"}]\n'
    elif [[ "$scenario" == "create" ]]; then
      printf '[]\n'
    else
      printf '[{"id":"skill-ceo","name":"CEO Skill"}]\n'
    fi
    ;;
  "skill get")
    if [[ "$scenario" == "retry" && ! -f "$SYNC_TEST_STATE/skill-get-failed-once" ]]; then
      touch "$SYNC_TEST_STATE/skill-get-failed-once"
      printf 'temporary network failure\n' >&2
      exit 1
    fi
    if [[ "$scenario" == "matched" || "$scenario" == "retry" ]]; then
      content="$(json_string_from_file "$SYNC_TEST_ROOT/agents/ceo/skill.md")"
    else
      content='"remote skill"'
    fi
    printf '{"id":"skill-ceo","name":"CEO Skill","content":%s}\n' "$content"
    ;;
  "skill update")
    ;;
  "skill create")
    printf '{"id":"skill-created","name":"CEO Skill"}\n'
    ;;
  "agent list")
    if [[ "$scenario" == "matched" || "$scenario" == "retry" ]]; then
      instructions="$(json_string_from_file "$SYNC_TEST_ROOT/agents/ceo/personality.md")"
    else
      instructions='"remote personality"'
    fi
    if [[ "$scenario" == "duplicate-agent" ]]; then
      printf '[{"id":"agent-one","name":"CEO","instructions":%s},{"id":"agent-two","name":"CEO","instructions":%s}]\n' "$instructions" "$instructions"
    else
      printf '[{"id":"agent-ceo","name":"CEO","instructions":%s}]\n' "$instructions"
    fi
    ;;
  "agent update")
    ;;
  "agent skills")
    if [[ "$3" == "list" ]]; then
      if [[ "$scenario" == "matched" || "$scenario" == "retry" ]]; then
        printf '[{"id":"skill-ceo","name":"CEO Skill","enabled":true}]\n'
      else
        printf '[]\n'
      fi
    elif [[ "$3" == "add" ]]; then
      :
    else
      exit 2
    fi
    ;;
  "workspace get")
    if [[ "$scenario" == "matched" || "$scenario" == "retry" ]]; then
      context="$(json_string_from_file "$SYNC_TEST_ROOT/workspace-context.md")"
    else
      context='"remote context"'
    fi
    printf '{"id":"workspace-test","name":"Test Workspace","context":%s}\n' "$context"
    ;;
  "workspace update")
    cat > /dev/null
    ;;
  *)
    printf 'unexpected multica command: %s\n' "$*" >&2
    exit 2
    ;;
esac
STUB
  chmod +x "$tmp/bin/multica" "$tmp/repo/scripts/sync-multica.sh"
  cat > "$tmp/bin/column" << 'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "$tmp/bin/column"
  git -C "$tmp/repo" init -q -b main
  git -C "$tmp/repo" config user.name 'Sync Test'
  git -C "$tmp/repo" config user.email 'sync-test@example.invalid'
  git -C "$tmp/repo" add .
  git -C "$tmp/repo" commit -qm fixture
  git -C "$tmp/repo" update-ref refs/remotes/origin/main HEAD
  printf '%s' "$tmp"
}

run_fixture() {
  local tmp="$1"
  shift
  PATH="$tmp/bin:$PATH" \
    SYNC_TEST_ROOT="$tmp/repo" \
    SYNC_TEST_STATE="$tmp/state" \
    MULTICA_WORKSPACE_ID="workspace-test" \
    "$tmp/repo/scripts/sync-multica.sh" --agent ceo "$@"
}

test_dry_run_plans_all_managed_resources() {
  local tmp
  tmp="$(make_fixture drift)"
  run_fixture "$tmp" > "$tmp/stdout" 2> "$tmp/stderr"
  assert_contains "$tmp/stderr" $'workspace\tcontext\tTest Workspace\twould update'
  assert_contains "$tmp/stderr" $'ceo\tskill\tCEO Skill\twould update'
  assert_contains "$tmp/stderr" $'ceo\tagent\tCEO\twould update'
  assert_contains "$tmp/stderr" $'ceo\tattachment\tCEO\twould attach'
  ! grep -Fq 'workspace update' "$tmp/state/calls.log" || fail "dry-run performed a workspace write"
  ! grep -Fq 'skill update' "$tmp/state/calls.log" || fail "dry-run performed a skill write"
  ! grep -Fq 'agent update' "$tmp/state/calls.log" || fail "dry-run performed an agent write"
}

test_apply_writes_context_content_instructions_and_attachment() {
  local tmp
  tmp="$(make_fixture drift)"
  run_fixture "$tmp" --apply > "$tmp/stdout" 2> "$tmp/stderr"
  assert_contains "$tmp/state/calls.log" 'workspace update workspace-test --context-stdin'
  assert_contains "$tmp/state/calls.log" 'skill update skill-ceo --content-file agents/ceo/skill.md'
  assert_contains "$tmp/state/calls.log" 'agent update agent-ceo --instructions desired personality'
  assert_contains "$tmp/state/calls.log" 'agent skills add agent-ceo --skill-ids skill-ceo'
}

test_verify_passes_only_on_converged_state() {
  local tmp
  tmp="$(make_fixture matched)"
  run_fixture "$tmp" --verify > "$tmp/stdout" 2> "$tmp/stderr"
  assert_contains "$tmp/stderr" $'workspace\tcontext\tTest Workspace\tup-to-date'
  assert_contains "$tmp/stderr" $'ceo\tattachment\tCEO\tattached'

  tmp="$(make_fixture drift)"
  if run_fixture "$tmp" --verify > "$tmp/stdout" 2> "$tmp/stderr"; then
    fail "verify unexpectedly passed with remote drift"
  fi
  assert_contains "$tmp/stderr" 'remote Multica state does not match this repository'
}

test_workspace_guard_fails_closed() {
  local tmp
  tmp="$(make_fixture matched)"
  if PATH="$tmp/bin:$PATH" \
      SYNC_TEST_ROOT="$tmp/repo" \
      SYNC_TEST_STATE="$tmp/state" \
      MULTICA_WORKSPACE_ID="wrong-workspace" \
      "$tmp/repo/scripts/sync-multica.sh" --agent ceo > "$tmp/stdout" 2> "$tmp/stderr"; then
    fail "workspace mismatch unexpectedly passed"
  fi
  assert_contains "$tmp/stderr" 'refusing to sync the wrong workspace'
}

test_apply_preflight_blocks_partial_writes() {
  local tmp
  tmp="$(make_fixture drift)"
  if PATH="$tmp/bin:$PATH" \
      SYNC_TEST_ROOT="$tmp/repo" \
      SYNC_TEST_STATE="$tmp/state" \
      MULTICA_WORKSPACE_ID="workspace-test" \
      SYNC_AGENT_CEO="Missing CEO" \
      "$tmp/repo/scripts/sync-multica.sh" --agent ceo --apply > "$tmp/stdout" 2> "$tmp/stderr"; then
    fail "apply unexpectedly passed with an unmapped agent"
  fi
  assert_contains "$tmp/stderr" 'No remote writes were attempted'
  ! grep -Fq 'workspace update' "$tmp/state/calls.log" || fail "preflight failure allowed a workspace write"
  ! grep -Fq 'skill update' "$tmp/state/calls.log" || fail "preflight failure allowed a skill write"
}

test_transient_reads_are_retried() {
  local tmp count
  tmp="$(make_fixture retry)"
  SYNC_READ_RETRY_DELAY=0 run_fixture "$tmp" --verify > "$tmp/stdout" 2> "$tmp/stderr"
  count="$(grep -Fc 'skill get skill-ceo --output json' "$tmp/state/calls.log")"
  [[ "$count" == "2" ]] || fail "expected skill get to retry once, got $count calls"
  assert_contains "$tmp/stderr" 'read failed (attempt 1/3)'
}

test_apply_requires_clean_main_at_origin() {
  local tmp
  tmp="$(make_fixture drift)"
  printf '%s\n' dirty >> "$tmp/repo/workspace-context.md"
  if run_fixture "$tmp" --apply > "$tmp/stdout" 2> "$tmp/stderr"; then
    fail "apply unexpectedly passed from a dirty checkout"
  fi
  assert_contains "$tmp/stderr" "requires a clean working tree"
  [[ ! -f "$tmp/state/calls.log" ]] || fail "dirty-checkout guard contacted Multica"

  tmp="$(make_fixture drift)"
  git -C "$tmp/repo" switch -qc feature
  if run_fixture "$tmp" --apply > "$tmp/stdout" 2> "$tmp/stderr"; then
    fail "apply unexpectedly passed from a non-main branch"
  fi
  assert_contains "$tmp/stderr" "requires branch 'main'"
}

test_ambiguous_resources_fail_before_apply() {
  local tmp
  tmp="$(make_fixture duplicate-agent)"
  if run_fixture "$tmp" --apply > "$tmp/stdout" 2> "$tmp/stderr"; then
    fail "apply unexpectedly passed with duplicate agent names"
  fi
  assert_contains "$tmp/stderr" "server agents matching 'CEO'"
  ! grep -Fq 'workspace update' "$tmp/state/calls.log" || fail "ambiguous agent allowed a write"

  tmp="$(make_fixture duplicate-skill)"
  if run_fixture "$tmp" --apply > "$tmp/stdout" 2> "$tmp/stderr"; then
    fail "apply unexpectedly passed with duplicate skill names"
  fi
  assert_contains "$tmp/stderr" "server skills matching 'CEO Skill'"
  ! grep -Fq 'workspace update' "$tmp/state/calls.log" || fail "ambiguous skill allowed a write"
}

test_created_skill_is_attached_in_same_apply() {
  local tmp
  tmp="$(make_fixture create)"
  run_fixture "$tmp" --apply > "$tmp/stdout" 2> "$tmp/stderr"
  assert_contains "$tmp/state/calls.log" 'skill create --name CEO Skill'
  assert_contains "$tmp/state/calls.log" 'agent skills add agent-ceo --skill-ids skill-created'
}

test_dry_run_plans_all_managed_resources
test_apply_writes_context_content_instructions_and_attachment
test_verify_passes_only_on_converged_state
test_workspace_guard_fails_closed
test_apply_preflight_blocks_partial_writes
test_transient_reads_are_retried
test_apply_requires_clean_main_at_origin
test_ambiguous_resources_fail_before_apply
test_created_skill_is_attached_in_same_apply
printf 'PASS: sync-multica desired-state tests\n'
