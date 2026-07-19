#!/usr/bin/env bash
# sync-multica.sh — push profession content to the Multica server.
#
# Multica has no git-sync: agent instructions and skills live server-side.
# This script is the bridge from this repo to the server:
#   - workspace-context.md                  → `multica workspace update --context-stdin`
# For every profession directory under agents/:
#   - skill : agents/<role>/skill.md       → `multica skill update` (create when absent)
#   - agent : agents/<role>/personality.md → `multica agent update --instructions`
#   - mount : resolved profession skill     → `multica agent skills add`
#
# Dry-run by default: prints the plan and makes no writes. Pass --apply to
# execute, then use --verify for a fresh read that fails on any remaining drift.
#
# Auth is ambient (`multica login` / MULTICA_SERVER_URL / MULTICA_WORKSPACE_ID).
# This script never reads, stores, or embeds tokens.
#
# Mapping conventions (override via env when server naming differs):
#   skill name  : "<Display> Skill" (CEO Skill, Engineer Skill, ...)
#                 override: SYNC_SKILL_<ROLE>
#   agent names : display name; engineer maps to BOTH instances
#                 (Engineer-A + Engineer-B — they share one profession dir)
#                 override: SYNC_AGENT_<ROLE>  (comma-separated names or ids)
# <ROLE> is the directory name uppercased with hyphens as underscores.
#
# Deliberately out of scope — explicit failure over guessing wrong:
#   - agent create: an unmapped agent fails the run with instructions;
#     create the agent in Multica (or set SYNC_AGENT_<ROLE>) and re-run.
#   - model/runtime changes: append --model / --runtime-id to the printed
#     `multica agent update` command manually. Desired models per role are
#     documented in README.md.
#
# Usage:
#   scripts/sync-multica.sh                  # dry run, all roles
#   scripts/sync-multica.sh --agent orchestrator  # dry run, one role
#   scripts/sync-multica.sh --apply          # execute, all roles
#   scripts/sync-multica.sh --apply --agent engineer
#   scripts/sync-multica.sh --verify         # read-only; nonzero on any drift

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

log() { printf '%s\n' "$*" >&2; }
die() {
  log "error: $*"
  exit 1
}

READ_RETRIES="${SYNC_READ_RETRIES:-3}"
READ_RETRY_DELAY="${SYNC_READ_RETRY_DELAY:-1}"

read_json_with_retry() { # output-file error-file command...
  local output_file="$1" error_file="$2" attempt
  shift 2
  for ((attempt = 1; attempt <= READ_RETRIES; attempt++)); do
    if "$@" > "$output_file" 2> "$error_file"; then
      return 0
    fi
    if (( attempt < READ_RETRIES )); then
      log "read failed (attempt $attempt/$READ_RETRIES); retrying in ${READ_RETRY_DELAY}s: $1 $2"
      sleep "$READ_RETRY_DELAY"
    fi
  done
  return 1
}

usage() {
  sed -n '2,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ---------- Arguments ----------

APPLY=0
VERIFY=0
ONLY_ROLE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --verify)
      VERIFY=1
      shift
      ;;
    --agent)
      [[ $# -ge 2 ]] || die "--agent requires a role name (a directory under agents/)"
      ONLY_ROLE="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1 (see --help)"
      ;;
  esac
done

[[ "$APPLY" -eq 0 || "$VERIFY" -eq 0 ]] \
  || die "--apply and --verify are mutually exclusive"

# ---------- Preconditions: fail loud, never guess ----------

check_apply_checkout() {
  local branch
  command -v git > /dev/null 2>&1 \
    || die "git not found on PATH; cannot prove that this checkout is safe to apply."
  git rev-parse --is-inside-work-tree > /dev/null 2>&1 \
    || die "--apply requires a Git checkout."
  branch="$(git branch --show-current)"
  [[ "$branch" == "main" ]] \
    || die "--apply requires branch 'main' (current: ${branch:-detached})."
  [[ -z "$(git status --porcelain)" ]] \
    || die "--apply requires a clean working tree; commit or otherwise resolve local changes first."
  git rev-parse --verify origin/main > /dev/null 2>&1 \
    || die "--apply cannot verify origin/main. Run 'git fetch origin main' first."
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
    || die "--apply requires HEAD to equal origin/main. Run 'git fetch origin main' and reconcile first."
}

if [[ "$APPLY" -eq 1 ]]; then
  check_apply_checkout
fi

command -v multica > /dev/null 2>&1 \
  || die "multica CLI not found on PATH. Install it (brew install multica) and run 'multica login', then re-run."
command -v python3 > /dev/null 2>&1 \
  || die "python3 not found on PATH (required for JSON parsing)."

# `column` is absent from some minimal environments. The summary renders
# AFTER all writes have happened, so it must never fail the run (a missing
# binary would exit 127 at the very end — in --apply, after server updates
# already landed). Detect it once up front and fall back to plain
# tab-separated output when it is missing or fails.
HAVE_COLUMN=0
command -v column > /dev/null 2>&1 && HAVE_COLUMN=1

render_table() { # reads TSV on stdin, writes the formatted table to stderr
  local tsv
  tsv="$(cat)"
  if [[ "$HAVE_COLUMN" -eq 1 ]]; then
    if printf '%s\n' "$tsv" | column -t -s $'\t' >&2; then
      return 0
    fi
    log "(column failed; printing plain tab-separated output)"
  fi
  printf '%s\n' "$tsv" >&2
}

[[ -d agents ]] || die "no agents/ directory at $REPO_ROOT — run from the agent-team checkout."
[[ -f workspace-context.md ]] || die "workspace-context.md not found at $REPO_ROOT."

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

SKILLS_JSON="$WORK_DIR/skills.json"
AGENTS_JSON="$WORK_DIR/agents.json"
WORKSPACE_JSON="$WORK_DIR/workspace.json"

if ! read_json_with_retry "$SKILLS_JSON" "$WORK_DIR/skill-list.err" \
    multica skill list --output json; then
  log "multica skill list failed:"
  cat "$WORK_DIR/skill-list.err" >&2
  die "cannot read server state. Check 'multica login' / MULTICA_WORKSPACE_ID and re-run."
fi
if ! read_json_with_retry "$AGENTS_JSON" "$WORK_DIR/agent-list.err" \
    multica agent list --output json; then
  log "multica agent list failed:"
  cat "$WORK_DIR/agent-list.err" >&2
  die "cannot read server state. Check 'multica login' / MULTICA_WORKSPACE_ID and re-run."
fi
if ! read_json_with_retry "$WORKSPACE_JSON" "$WORK_DIR/workspace-get.err" \
    multica workspace get --output json; then
  log "multica workspace get failed:"
  cat "$WORK_DIR/workspace-get.err" >&2
  die "cannot read the selected workspace. Check 'multica auth status' and re-run."
fi

SELECTED_WORKSPACE_ID="$(python3 - "$WORKSPACE_JSON" << 'PY'
import json, sys
print(json.load(open(sys.argv[1])).get("id") or "")
PY
)"
[[ -n "$SELECTED_WORKSPACE_ID" ]] || die "selected workspace response has no id."
if [[ -n "${MULTICA_WORKSPACE_ID:-}" && "$MULTICA_WORKSPACE_ID" != "$SELECTED_WORKSPACE_ID" ]]; then
  die "MULTICA_WORKSPACE_ID does not match the workspace selected by the CLI; refusing to sync the wrong workspace."
fi

# ---------- Naming conventions ----------

# ceo -> CEO, pm -> PM, gtm -> GTM, engineer -> Engineer, ...
display_name() {
  local role="$1"
  if [[ ${#role} -le 3 ]]; then
    printf '%s' "$role" | tr '[:lower:]' '[:upper:]'
  else
    printf '%s%s' "$(printf '%.1s' "$role" | tr '[:lower:]' '[:upper:]')" "${role:1}"
  fi
}

# ceo -> CEO, engineer -> ENGINEER (for SYNC_*_<ROLE> env lookups)
env_suffix() {
  printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_'
}

skill_name_for() {
  local role="$1" override_var
  override_var="SYNC_SKILL_$(env_suffix "$role")"
  if [[ -n "${!override_var:-}" ]]; then
    printf '%s' "${!override_var}"
  else
    printf '%s Skill' "$(display_name "$role")"
  fi
}

# Comma-separated server agent names (or ids) that receive this role's
# personality.md as instructions. Engineer has two instances by design.
agent_targets_for() {
  local role="$1" override_var
  override_var="SYNC_AGENT_$(env_suffix "$role")"
  if [[ -n "${!override_var:-}" ]]; then
    printf '%s' "${!override_var}"
  elif [[ "$role" == "engineer" ]]; then
    printf 'Engineer-A,Engineer-B'
  elif [[ "$role" == "evaluator" ]]; then
    printf 'Evaluator-A,Evaluator-B'
  else
    display_name "$role"
  fi
}

# ---------- JSON lookups (read-only, against the cached list output) ----------

# Prints "<id>\t<name>" for the skill whose name EXACTLY matches the resolved
# name (case-insensitive), nothing when absent, or "AMBIGUOUS\t<count>" when
# the server contains duplicates. Exact-match only, no
# alternate-name fallback: when SYNC_SKILL_<ROLE> is set, matching anything
# other than that override (e.g. the default "<Role> Skill" name) would
# silently update the WRONG remote skill. An absent name falls through to the
# create path in sync_skill. The default-name convention applies only when no
# override is configured, and is resolved in skill_name_for — not here.
lookup_skill() {
  python3 - "$SKILLS_JSON" "$1" << 'PY'
import json, sys
skills = json.load(open(sys.argv[1]))
want = sys.argv[2].strip().lower()
matches = [s for s in skills if (s.get("name") or "").strip().lower() == want]
if len(matches) > 1:
    print(f'AMBIGUOUS\t{len(matches)}')
elif matches:
    s = matches[0]
    print(f'{s["id"]}\t{(s.get("name") or "").strip()}')
PY
}

# Prints "<id>\t<name>" for the agent matching the target (id exact or name
# case-insensitive), nothing when absent, or "AMBIGUOUS\t<count>" for a
# duplicated name. An exact id remains unambiguous.
lookup_agent() {
  python3 - "$AGENTS_JSON" "$1" << 'PY'
import json, sys
agents = json.load(open(sys.argv[1]))
target = sys.argv[2].strip()
id_matches = [a for a in agents if a.get("id") == target]
if id_matches:
    a = id_matches[0]
    print(f'{a["id"]}\t{(a.get("name") or "").strip()}')
else:
    matches = [a for a in agents if (a.get("name") or "").strip().lower() == target.lower()]
    if len(matches) > 1:
        print(f'AMBIGUOUS\t{len(matches)}')
    elif matches:
        a = matches[0]
        print(f'{a["id"]}\t{(a.get("name") or "").strip()}')
PY
}

# Writes the remote skill content to stdout.
remote_skill_content() {
  local skill_id="$1" raw="$WORK_DIR/skill-$1.json" err="$WORK_DIR/skill-$1.err"
  if ! read_json_with_retry "$raw" "$err" multica skill get "$skill_id" --output json; then
    cat "$err" >&2
    return 1
  fi
  python3 - "$raw" << 'PY'
import json, sys
sys.stdout.write(json.load(open(sys.argv[1])).get("content") or "")
PY
}

# Writes the remote agent instructions (from the cached list) to stdout.
remote_agent_instructions() {
  python3 - "$AGENTS_JSON" "$1" << 'PY'
import json, sys
for a in json.load(open(sys.argv[1])):
    if a.get("id") == sys.argv[2]:
        sys.stdout.write(a.get("instructions") or "")
        break
PY
}

# Trailing-newline-insensitive comparison: `--instructions "$(cat file)"`
# strips trailing newlines, so an exact byte compare would report perpetual
# drift on otherwise-identical content.
same_content() {
  python3 - "$1" "$2" << 'PY'
import sys
a = open(sys.argv[1], encoding="utf-8").read().rstrip("\n")
b = open(sys.argv[2], encoding="utf-8").read().rstrip("\n")
sys.exit(0 if a == b else 1)
PY
}

# ---------- Summary bookkeeping ----------

SUMMARY_ROWS=()
ERRORS=0
DRIFT=0

add_row() { # role resource target status
  SUMMARY_ROWS+=("$(printf '%s\t%s\t%s\t%s' "$1" "$2" "$3" "$4")")
}

mark_drift() {
  DRIFT=$((DRIFT + 1))
}

# ---------- Sync: workspace constitution ----------

sync_workspace_context() {
  local file="workspace-context.md" workspace_name status
  workspace_name="$(python3 - "$WORKSPACE_JSON" << 'PY'
import json, sys
print(json.load(open(sys.argv[1])).get("name") or "")
PY
)"
  python3 - "$WORKSPACE_JSON" > "$WORK_DIR/remote-context" << 'PY'
import json, sys
sys.stdout.write(json.load(open(sys.argv[1])).get("context") or "")
PY

  if same_content "$file" "$WORK_DIR/remote-context"; then
    add_row "workspace" "context" "$workspace_name" "up-to-date"
    return 0
  fi

  mark_drift
  log "[workspace] context differs — update"
  log "  \$ multica workspace update <selected-workspace> --context-stdin < $file"
  if [[ "$APPLY" -eq 1 ]]; then
    if multica workspace update "$SELECTED_WORKSPACE_ID" --context-stdin < "$file" > /dev/null; then
      status="updated"
    else
      status="failed"
      ERRORS=$((ERRORS + 1))
    fi
  elif [[ "$VERIFY" -eq 1 ]]; then
    status="drift"
  else
    status="would update"
  fi
  add_row "workspace" "context" "$workspace_name" "$status"
}

# ---------- Sync: one skill per role ----------

sync_skill() {
  local role="$1" file="agents/$1/skill.md"
  local name match skill_id remote_name status created_json

  if [[ ! -f "$file" ]]; then
    log "[$role] skip skill: $file not found"
    add_row "$role" "skill" "-" "skip (no skill.md)"
    return 0
  fi

  # Exact-match lookup on the resolved name only. With SYNC_SKILL_<ROLE> set,
  # an absent override name means CREATE under that name — never fall back to
  # updating a skill under the default "<Display> Skill" name.
  name="$(skill_name_for "$role")"
  match="$(lookup_skill "$name")"

  if [[ "$match" == AMBIGUOUS$'\t'* ]]; then
    log "[$role] multiple server skills match '$name'; refusing to guess."
    add_row "$role" "skill" "$name" "ambiguous (${match#*$'\t'} matches)"
    ERRORS=$((ERRORS + 1))
    return 0
  fi

  if [[ -z "$match" ]]; then
    mark_drift
    log "[$role] skill '$name' not found on server — create"
    log "  \$ multica skill create --name '$name' --description 'Operational rules for the $(display_name "$role") agent. Self-contained.' --content-file $file"
    if [[ "$APPLY" -eq 1 ]]; then
      created_json="$WORK_DIR/created-skill-$role.json"
      if multica skill create \
        --name "$name" \
        --description "Operational rules for the $(display_name "$role") agent. Self-contained." \
        --content-file "$file" > "$created_json"; then
        skill_id="$(python3 - "$created_json" << 'PY'
import json, sys
print(json.load(open(sys.argv[1])).get("id") or "")
PY
)"
        if [[ -n "$skill_id" ]]; then
          printf '%s' "$skill_id" > "$WORK_DIR/skill-id-$role"
          status="created"
        else
          status="failed (create returned no id)"
          ERRORS=$((ERRORS + 1))
        fi
      else
        status="failed"
        ERRORS=$((ERRORS + 1))
      fi
    elif [[ "$VERIFY" -eq 1 ]]; then
      status="missing"
    else
      status="would create"
    fi
    add_row "$role" "skill" "$name" "$status"
    return 0
  fi

  skill_id="${match%%$'\t'*}"
  remote_name="${match#*$'\t'}"
  printf '%s' "$skill_id" > "$WORK_DIR/skill-id-$role"

  if ! remote_skill_content "$skill_id" > "$WORK_DIR/remote-skill"; then
    log "[$role] failed to fetch remote content for skill '$remote_name' ($skill_id)"
    add_row "$role" "skill" "$remote_name" "failed"
    ERRORS=$((ERRORS + 1))
    return 0
  fi

  if same_content "$file" "$WORK_DIR/remote-skill"; then
    add_row "$role" "skill" "$remote_name" "up-to-date"
    return 0
  fi

  log "[$role] skill '$remote_name' content differs — update"
  mark_drift
  log "  \$ multica skill update $skill_id --content-file $file"
  if [[ "$APPLY" -eq 1 ]]; then
    if multica skill update "$skill_id" --content-file "$file" > /dev/null; then
      status="updated"
    else
      status="failed"
      ERRORS=$((ERRORS + 1))
    fi
  elif [[ "$VERIFY" -eq 1 ]]; then
    status="drift"
  else
    status="would update"
  fi
  add_row "$role" "skill" "$remote_name" "$status"
}

# ---------- Sync: profession skill assignment ----------

sync_skill_attachment() {
  local role="$1" agent_id="$2" agent_name="$3"
  local skill_id status assigned_json

  [[ -f "agents/$role/skill.md" ]] || return 0
  if [[ ! -f "$WORK_DIR/skill-id-$role" ]]; then
    mark_drift
    if [[ "$VERIFY" -eq 1 ]]; then
      add_row "$role" "attachment" "$agent_name" "missing skill"
    elif [[ "$APPLY" -eq 0 ]]; then
      add_row "$role" "attachment" "$agent_name" "would attach after create"
    else
      add_row "$role" "attachment" "$agent_name" "failed (skill id unavailable)"
      ERRORS=$((ERRORS + 1))
    fi
    return 0
  fi
  skill_id="$(cat "$WORK_DIR/skill-id-$role")"
  assigned_json="$WORK_DIR/assigned-$agent_id.json"
  if ! read_json_with_retry "$assigned_json" "$WORK_DIR/assigned-$agent_id.err" \
      multica agent skills list "$agent_id" --output json; then
    log "[$role] failed to list skills assigned to '$agent_name':"
    cat "$WORK_DIR/assigned-$agent_id.err" >&2
    add_row "$role" "attachment" "$agent_name" "failed"
    ERRORS=$((ERRORS + 1))
    return 0
  fi
  if python3 - "$assigned_json" "$skill_id" << 'PY'
import json, sys
skills = json.load(open(sys.argv[1]))
sys.exit(0 if any(s.get("id") == sys.argv[2] and s.get("enabled", True) for s in skills) else 1)
PY
  then
    add_row "$role" "attachment" "$agent_name" "attached"
    return 0
  fi

  mark_drift
  log "[$role] profession skill is not attached to '$agent_name' — add"
  log "  \$ multica agent skills add $agent_id --skill-ids $skill_id"
  if [[ "$APPLY" -eq 1 ]]; then
    if multica agent skills add "$agent_id" --skill-ids "$skill_id" > /dev/null; then
      status="attached"
    else
      status="failed"
      ERRORS=$((ERRORS + 1))
    fi
  elif [[ "$VERIFY" -eq 1 ]]; then
    status="missing"
  else
    status="would attach"
  fi
  add_row "$role" "attachment" "$agent_name" "$status"
}

# ---------- Sync: agent instructions per role (engineer: two instances) ----------

sync_agents() {
  local role="$1" file="agents/$1/personality.md"
  local targets target match agent_id agent_name status

  if [[ ! -f "$file" ]]; then
    log "[$role] skip agent instructions: $file not found"
    add_row "$role" "agent" "-" "skip (no personality.md)"
    return 0
  fi

  targets="$(agent_targets_for "$role")"
  local IFS=','
  for target in $targets; do
    target="$(printf '%s' "$target" | sed 's/^ *//;s/ *$//')"
    [[ -n "$target" ]] || continue

    match="$(lookup_agent "$target")"
    if [[ "$match" == AMBIGUOUS$'\t'* ]]; then
      log "[$role] multiple server agents match '$target'; use an exact id in SYNC_AGENT_$(env_suffix "$role")."
      add_row "$role" "agent" "$target" "ambiguous (${match#*$'\t'} matches)"
      ERRORS=$((ERRORS + 1))
      continue
    fi
    if [[ -z "$match" ]]; then
      log "[$role] no server agent matches '$target'."
      log "  Create the agent in Multica, or set SYNC_AGENT_$(env_suffix "$role")=<name-or-id>[,<name-or-id>] and re-run."
      add_row "$role" "agent" "$target" "unmapped"
      ERRORS=$((ERRORS + 1))
      continue
    fi

    agent_id="${match%%$'\t'*}"
    agent_name="${match#*$'\t'}"

    remote_agent_instructions "$agent_id" > "$WORK_DIR/remote-instructions"
    if same_content "$file" "$WORK_DIR/remote-instructions"; then
      add_row "$role" "agent" "$agent_name" "up-to-date"
    else
      mark_drift
      log "[$role] agent '$agent_name' instructions differ — update"
      log "  \$ multica agent update $agent_id --instructions \"\$(cat $file)\""
      if [[ "$APPLY" -eq 1 ]]; then
        if multica agent update "$agent_id" --instructions "$(cat "$file")" > /dev/null; then
          status="updated"
        else
          status="failed"
          ERRORS=$((ERRORS + 1))
        fi
      elif [[ "$VERIFY" -eq 1 ]]; then
        status="drift"
      else
        status="would update"
      fi
      add_row "$role" "agent" "$agent_name" "$status"
    fi
    sync_skill_attachment "$role" "$agent_id" "$agent_name"
  done
}

# Resolve every target before the first write. A direct --apply invocation must
# never update workspace/skills and only then discover that a later role is
# unmapped. Also reject one server agent mapped to two professions: that would
# mount conflicting instructions under a seemingly successful plan.
preflight_apply_resources() {
  local role targets target match agent_id prior skill_name errors=0
  local seen="$WORK_DIR/preflight-agent-ids"
  : > "$seen"
  for role in "${ROLES[@]}"; do
    if [[ -f "agents/$role/skill.md" ]]; then
      skill_name="$(skill_name_for "$role")"
      match="$(lookup_skill "$skill_name")"
      if [[ "$match" == AMBIGUOUS$'\t'* ]]; then
        log "[preflight] $role has ${match#*$'\t'} server skills matching '$skill_name'."
        errors=$((errors + 1))
      fi
    fi
    targets="$(agent_targets_for "$role")"
    local IFS=','
    for target in $targets; do
      target="$(printf '%s' "$target" | sed 's/^ *//;s/ *$//')"
      [[ -n "$target" ]] || continue
      match="$(lookup_agent "$target")"
      if [[ "$match" == AMBIGUOUS$'\t'* ]]; then
        log "[preflight] $role has ${match#*$'\t'} server agents matching '$target'; use an exact id."
        errors=$((errors + 1))
        continue
      fi
      if [[ -z "$match" ]]; then
        log "[preflight] $role has no server agent matching '$target'."
        errors=$((errors + 1))
        continue
      fi
      agent_id="${match%%$'\t'*}"
      prior="$(grep -F "${agent_id}"$'\t' "$seen" | head -1 || true)"
      if [[ -n "$prior" ]]; then
        log "[preflight] agent '$target' is mapped more than once (${prior#*$'\t'} and $role); refusing conflicting profession assignments."
        errors=$((errors + 1))
        continue
      fi
      printf '%s\t%s\n' "$agent_id" "$role" >> "$seen"
    done
  done
  [[ "$errors" -eq 0 ]] \
    || die "$errors resource mapping error(s) found before apply. No remote writes were attempted."
}

# ---------- Main ----------

ROLES=()
for dir in agents/*/; do
  [[ -d "$dir" ]] || continue
  ROLES+=("$(basename "$dir")")
done
[[ ${#ROLES[@]} -gt 0 ]] || die "no profession directories found under agents/."

if [[ -n "$ONLY_ROLE" ]]; then
  [[ -d "agents/$ONLY_ROLE" ]] \
    || die "agents/$ONLY_ROLE does not exist. Available roles: ${ROLES[*]}"
  ROLES=("$ONLY_ROLE")
fi

if [[ "$APPLY" -eq 1 ]]; then
  preflight_apply_resources
fi

if [[ "$APPLY" -eq 1 ]]; then
  log "APPLY mode: changes will be written to the Multica server."
elif [[ "$VERIFY" -eq 1 ]]; then
  log "VERIFY mode: read-only; any drift fails the run."
else
  log "DRY RUN (no changes made). Re-run with --apply to execute."
fi
log ""

sync_workspace_context

for role in "${ROLES[@]}"; do
  sync_skill "$role"
  sync_agents "$role"
done

# ---------- Summary table ----------

log ""
log "Summary:"
{
  printf 'ROLE\tRESOURCE\tTARGET\tSTATUS\n'
  printf '%s\n' "${SUMMARY_ROWS[@]}"
} | render_table

if [[ "$ERRORS" -gt 0 ]]; then
  log ""
  die "$ERRORS item(s) unmapped or failed — see rows above. Nothing was guessed; fix the mapping and re-run."
fi
if [[ "$VERIFY" -eq 1 && "$DRIFT" -gt 0 ]]; then
  log ""
  die "$DRIFT drift item(s) remain — remote Multica state does not match this repository."
fi
