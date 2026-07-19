#!/usr/bin/env bash
# sync-multica.sh — push repo desired state (agents/<role>/) to the Multica server.
#
# Multica has no git-sync: agent instructions and skills live server-side.
# This script is the bridge from this repo to the server. For every
# profession directory under agents/:
#   - skill : agents/<role>/skill.md       → `multica skill update` (create when absent)
#   - agent : agents/<role>/personality.md → `multica agent update --instructions`
#
# Dry-run by default: prints the commands it would run plus a summary table
# and makes no writes. Pass --apply to execute.
#
# Auth is ambient (`multica login` / MULTICA_SERVER_URL / MULTICA_WORKSPACE_ID).
# This script never reads, stores, or embeds tokens.
#
# Mapping conventions (override via env when server naming differs):
#   skill name  : "<Display> Skill" (CEO Skill, Engineer Skill, ...)
#                 override: SYNC_SKILL_<ROLE>  (e.g. SYNC_SKILL_CEO="CEO Skill")
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
#   scripts/sync-multica.sh --agent ceo      # dry run, one role
#   scripts/sync-multica.sh --apply          # execute, all roles
#   scripts/sync-multica.sh --apply --agent engineer

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

log() { printf '%s\n' "$*" >&2; }
die() {
  log "error: $*"
  exit 1
}

usage() {
  sed -n '2,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ---------- Arguments ----------

APPLY=0
ONLY_ROLE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=1
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

# ---------- Preconditions: fail loud, never guess ----------

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

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

SKILLS_JSON="$WORK_DIR/skills.json"
AGENTS_JSON="$WORK_DIR/agents.json"

if ! multica skill list --output json > "$SKILLS_JSON" 2> "$WORK_DIR/skill-list.err"; then
  log "multica skill list failed:"
  cat "$WORK_DIR/skill-list.err" >&2
  die "cannot read server state. Check 'multica login' / MULTICA_WORKSPACE_ID and re-run."
fi
if ! multica agent list --output json > "$AGENTS_JSON" 2> "$WORK_DIR/agent-list.err"; then
  log "multica agent list failed:"
  cat "$WORK_DIR/agent-list.err" >&2
  die "cannot read server state. Check 'multica login' / MULTICA_WORKSPACE_ID and re-run."
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
  else
    display_name "$role"
  fi
}

# ---------- JSON lookups (read-only, against the cached list output) ----------

# Prints "<id>\t<name>" for the skill whose name EXACTLY matches the resolved
# name (case-insensitive), or nothing when absent. Exact-match only, no
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
for s in skills:
    name = (s.get("name") or "").strip()
    if name.lower() == want:
        print(f'{s["id"]}\t{name}')
        break
PY
}

# Prints "<id>\t<name>" for the agent matching the target (id exact or name
# case-insensitive), or nothing when absent.
lookup_agent() {
  python3 - "$AGENTS_JSON" "$1" << 'PY'
import json, sys
agents = json.load(open(sys.argv[1]))
target = sys.argv[2].strip()
for a in agents:
    name = (a.get("name") or "").strip()
    if a.get("id") == target or name.lower() == target.lower():
        print(f'{a["id"]}\t{name}')
        break
PY
}

# Writes the remote skill content to stdout.
remote_skill_content() {
  multica skill get "$1" --output json \
    | python3 -c 'import json,sys; sys.stdout.write(json.load(sys.stdin).get("content") or "")'
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

add_row() { # role resource target status
  SUMMARY_ROWS+=("$(printf '%s\t%s\t%s\t%s' "$1" "$2" "$3" "$4")")
}

# ---------- Sync: one skill per role ----------

sync_skill() {
  local role="$1" file="agents/$1/skill.md"
  local name match skill_id remote_name status

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

  if [[ -z "$match" ]]; then
    log "[$role] skill '$name' not found on server — create"
    log "  \$ multica skill create --name '$name' --description 'Operational rules for the $(display_name "$role") agent. Self-contained.' --content-file $file"
    if [[ "$APPLY" -eq 1 ]]; then
      if multica skill create \
        --name "$name" \
        --description "Operational rules for the $(display_name "$role") agent. Self-contained." \
        --content-file "$file" > /dev/null; then
        status="created"
      else
        status="failed"
        ERRORS=$((ERRORS + 1))
      fi
    else
      status="would create"
    fi
    add_row "$role" "skill" "$name" "$status"
    return 0
  fi

  skill_id="${match%%$'\t'*}"
  remote_name="${match#*$'\t'}"

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
  log "  \$ multica skill update $skill_id --content-file $file"
  if [[ "$APPLY" -eq 1 ]]; then
    if multica skill update "$skill_id" --content-file "$file" > /dev/null; then
      status="updated"
    else
      status="failed"
      ERRORS=$((ERRORS + 1))
    fi
  else
    status="would update"
  fi
  add_row "$role" "skill" "$remote_name" "$status"
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
      continue
    fi

    log "[$role] agent '$agent_name' instructions differ — update"
    log "  \$ multica agent update $agent_id --instructions \"\$(cat $file)\""
    if [[ "$APPLY" -eq 1 ]]; then
      if multica agent update "$agent_id" --instructions "$(cat "$file")" > /dev/null; then
        status="updated"
      else
        status="failed"
        ERRORS=$((ERRORS + 1))
      fi
    else
      status="would update"
    fi
    add_row "$role" "agent" "$agent_name" "$status"
  done
}

# ---------- Main ----------

if [[ "$APPLY" -eq 1 ]]; then
  log "APPLY mode: changes will be written to the Multica server."
else
  log "DRY RUN (no changes made). Re-run with --apply to execute."
fi
log ""

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
