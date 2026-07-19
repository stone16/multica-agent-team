#!/usr/bin/env bash
# setup-pr-webhooks.sh — batch-install the Multica PR-review webhook on GitHub.
#
# Squad v2 wires PR review to Multica through GitHub webhooks: pull_request,
# issue_comment, and pull_request_review events hit the Multica autopilot
# webhook URL, which triggers the pr-sweep pipeline for the referenced PR.
# This script installs those hooks across the opted-in owners.
#
# Per owner in scope:
#   - Organization where the caller is an active admin → ONE org-level hook
#     (covers every repo in the org, present and future).
#   - Anything else (user account, or org without admin) → per-repo hooks
#     across that owner's non-archived repositories.
#
# Credential hygiene (non-negotiable):
#   - MULTICA_WEBHOOK_URL embeds a bearer credential. It is read from the
#     environment only, never committed, never written to disk, never placed
#     on a command line (API bodies go to gh via stdin so the URL is not
#     visible in argv/ps), and never printed in full — logs show it as
#     scheme://host/<redacted>.
#   - MULTICA_REVIEW_SCOPE names the owners to touch (your personal account
#     plus explicitly opted-in orgs, newline/space-separated). There is no
#     default: without it the script refuses to run rather than enumerate
#     everything the token can see. Org names stay in env, not in files.
#
# Idempotent: existing hooks are listed first. A target counts as installed
# only when a hook points at the same URL AND is active, subscribes to
# EXACTLY the three required events (no extras — an extra event would fire
# the Multica autopilot on triggers the pipeline never asked for), uses
# content_type json, and has insecure_ssl "0". A URL match whose config has
# drifted is repaired in place (PATCH re-asserts the full desired state;
# GitHub replaces the events list wholesale, so extras are removed) instead
# of being silently skipped. The URL comparison
# happens inside gh's jq filter against the environment variable, so
# neither our URL nor any listed hook URL is ever logged or placed on a
# command line. This script creates and repairs only hooks that point at
# the Multica webhook URL; it never touches other hooks and never deletes.
# If the webhook URL is rotated, remove the old hooks manually.
#
# Dry-run by default: read-only API calls, then a plan table. --apply writes.
#
# Requires: gh with ambient auth. Token scopes: `repo` to enumerate
# repositories, `admin:repo_hook` for repo hooks, `admin:org_hook` for
# org-level hooks.
#
# Usage:
#   export MULTICA_WEBHOOK_URL='<paste from the Multica autopilot webhook config>'
#   export MULTICA_REVIEW_SCOPE='<your-login> <opted-in-org>'
#   scripts/setup-pr-webhooks.sh                 # dry run, all owners in scope
#   scripts/setup-pr-webhooks.sh --owner <name>  # dry run, one owner
#                                                # (<name> must be in scope)
#   scripts/setup-pr-webhooks.sh --apply         # execute
#   scripts/setup-pr-webhooks.sh --allow-insecure-url
#                                                # permit a plain http:// webhook
#                                                # URL — local testing only; the
#                                                # embedded bearer credential
#                                                # travels unencrypted. Without
#                                                # this flag, non-https URLs are
#                                                # rejected.

set -euo pipefail

log() { printf '%s\n' "$*" >&2; }
die() {
  log "error: $*"
  exit 1
}

usage() {
  awk 'NR == 1 { next } /^[^#]/ { exit } { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
}

# ---------- Arguments ----------

APPLY=0
ONLY_OWNER=""
ALLOW_INSECURE_URL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --allow-insecure-url)
      # Local testing only: permits a plain http:// MULTICA_WEBHOOK_URL even
      # though the embedded bearer credential then travels unencrypted.
      ALLOW_INSECURE_URL=1
      shift
      ;;
    --owner)
      [[ $# -ge 2 ]] || die "--owner requires an owner name (which must also appear in MULTICA_REVIEW_SCOPE)"
      ONLY_OWNER="$2"
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

command -v gh > /dev/null 2>&1 \
  || die "gh CLI not found on PATH. Install it and run 'gh auth login', then re-run."

# `column` is absent from some minimal environments. The summary renders
# AFTER all writes have happened, so it must never fail the run (a missing
# binary would exit 127 at the very end — in --apply, after hooks were
# already created). Detect it once up front and fall back to plain
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

WEBHOOK_URL="${MULTICA_WEBHOOK_URL:-}"
if [[ -z "$WEBHOOK_URL" ]]; then
  log "error: MULTICA_WEBHOOK_URL is not set."
  log ""
  log "  This is the Multica autopilot webhook URL. It embeds a bearer"
  log "  credential, so it lives in your shell environment only:"
  log "    export MULTICA_WEBHOOK_URL='<paste from the Multica autopilot webhook config>'"
  log "  Never commit it and never write it to a tracked file. This script"
  log "  logs it only as scheme://host/<redacted>."
  exit 1
fi

SCOPE_RAW="${MULTICA_REVIEW_SCOPE:-}"
if [[ -z "$SCOPE_RAW" ]]; then
  log "error: MULTICA_REVIEW_SCOPE is not set."
  log ""
  log "  Refusing to enumerate every owner the token can see. List the"
  log "  owners to install hooks for (your personal account plus explicitly"
  log "  opted-in orgs), newline- or space-separated:"
  log "    export MULTICA_REVIEW_SCOPE='<your-login> <opted-in-org>'"
  log "  Owner and org names may themselves be sensitive — keep them in the"
  log "  environment, not in tracked files."
  exit 1
fi

# The URL embeds a bearer credential, so plain http is a credential leak in
# transit: hard-reject it unless --allow-insecure-url (local testing only)
# was passed explicitly. The URL itself is never echoed here — not even in
# the rejection message.
case "$WEBHOOK_URL" in
  https://*) : ;;
  http://*)
    if [[ "$ALLOW_INSECURE_URL" -eq 1 ]]; then
      log "warning: MULTICA_WEBHOOK_URL uses plain http (--allow-insecure-url) — the embedded credential travels unencrypted. Local testing only."
    else
      log "error: MULTICA_WEBHOOK_URL uses plain http:// — the embedded bearer credential would travel unencrypted."
      log "  Use an https:// URL. For local testing only, re-run with --allow-insecure-url."
      exit 1
    fi
    ;;
  *)
    die "MULTICA_WEBHOOK_URL does not look like an absolute http(s):// URL."
    ;;
esac

# Redacted form for logs: scheme://host only; path/query (where the bearer
# credential lives) and any userinfo are dropped.
MASKED_WEBHOOK_URL="$(printf '%s' "$WEBHOOK_URL" \
  | sed -nE 's#^(https?://)([^/?@]*@)?([^/?]+).*#\1\3/<redacted>#p')"
[[ -n "$MASKED_WEBHOOK_URL" ]] || MASKED_WEBHOOK_URL='<redacted-webhook-url>'

# hook_records compares hook URLs against env.MULTICA_WEBHOOK_URL inside
# gh's jq filter — the URL stays out of argv and out of every log line.
# Re-export so the comparison works even when the variable was set without
# `export` (e.g. via `MULTICA_WEBHOOK_URL=... scripts/...` would export it,
# but a plain shell assignment would not).
export MULTICA_WEBHOOK_URL="$WEBHOOK_URL"

# ---------- Scope ----------

# Owners from MULTICA_REVIEW_SCOPE: split on whitespace/commas, drop blanks,
# treat a #-token as a comment running to end of line, dedupe preserving order.
scope_owners() {
  printf '%s\n' "$SCOPE_RAW" \
    | tr -d '\r' \
    | awk '
        {
          n = split($0, parts, /[ \t,]+/)
          for (i = 1; i <= n; i++) {
            p = parts[i]
            if (p ~ /^#/) break
            if (p == "") continue
            if (!seen[p]++) print p
          }
        }'
}

OWNERS="$(scope_owners || true)"
[[ -n "$OWNERS" ]] || die "MULTICA_REVIEW_SCOPE contains no usable owner names."

if [[ -n "$ONLY_OWNER" ]]; then
  printf '%s\n' "$OWNERS" | grep -Fxq "$ONLY_OWNER" \
    || die "--owner '$ONLY_OWNER' is not in MULTICA_REVIEW_SCOPE. Owners must be explicitly opted in via the env var; this script never widens scope on its own."
  OWNERS="$ONLY_OWNER"
fi

EVENTS_HUMAN="pull_request,issue_comment,pull_request_review"

# ---------- GitHub helpers ----------

# "User" or "Organization"; empty/failure when the owner cannot be resolved.
owner_type() {
  gh api "users/$1" --jq '.type' 2> /dev/null
}

# True when the authenticated caller is an active admin of the org — the
# requirement for the single org-level hook path. Non-members get a 404 from
# this endpoint and land here as non-admin, which falls back to per-repo hooks.
org_admin() {
  local out
  out="$(gh api "user/memberships/orgs/$1" --jq '"\(.state) \(.role)"' 2> /dev/null)" || return 1
  [[ "$out" == "active admin" ]]
}

# Upper bound passed to gh repo list. If an owner has this many non-archived
# repos, the listing may be truncated; process_owner flags that as a warning
# so a coverage gap is never silent.
REPO_LIST_LIMIT=1000

list_owner_repos() {
  gh repo list "$1" --limit "$REPO_LIST_LIMIT" --no-archived --json name --jq '.[].name'
}

# Prints one TSV line per existing hook on the target that points at the
# Multica webhook URL:
#   <id> <active> <events_ok> <content_type_ok> <ssl_ok> <missing> <extra>
# (fields 2-5 as yes/no; <missing>/<extra> are comma-joined event names, or
# "-" when empty). The URL comparison runs inside gh's jq filter against
# env.MULTICA_WEBHOOK_URL, so hook URLs (ours and any other service's,
# which frequently embed credentials) never appear in output, logs, or
# argv. events_ok demands exact SET EQUALITY (sorted events == the sorted
# required set), not mere membership: a hook subscribed to extra events
# would fire the Multica autopilot on triggers the pipeline never asked
# for, so extras are config drift just like missing events. Plain equality
# on sorted arrays also avoids jq's `contains`, whose substring matching on
# strings would let pull_request_review satisfy a pull_request requirement.
hook_records() {
  gh api "$1" --paginate --jq '
    ["issue_comment", "pull_request", "pull_request_review"] as $want
    | .[]
    | select((.config.url // "") == env.MULTICA_WEBHOOK_URL)
    | ((.events // []) | sort) as $ev
    | [ (.id | tostring),
        (if .active == true then "yes" else "no" end),
        (if $ev == $want then "yes" else "no" end),
        (if (.config.content_type // "") == "json" then "yes" else "no" end),
        (if ((.config.insecure_ssl // "") | tostring) == "0" then "yes" else "no" end),
        (($want - $ev) | if . == [] then "-" else join(",") end),
        (($ev - $want) | if . == [] then "-" else join(",") end) ]
    | @tsv' 2> /dev/null
}

# Set by hook_state for the drift case (return 3): the hook to PATCH and a
# human-readable list of what drifted (never contains the URL).
HOOK_ID=""
HOOK_DRIFT=""

# 0: a fully configured hook exists (active, EXACTLY the three required
#    events, json, ssl verification on) — nothing to do;
# 1: no hook points at the webhook URL — create;
# 2: cannot list hooks — refuse to act blind;
# 3: URL match but config drifted — update (HOOK_ID / HOOK_DRIFT set).
hook_state() {
  local api_path="$1" records id active events_ok ctype_ok ssl_ok drift
  local missing extra ev_detail
  HOOK_ID=""
  HOOK_DRIFT=""
  if ! records="$(hook_records "$api_path")"; then
    return 2
  fi
  [[ -n "$records" ]] || return 1
  while IFS=$'\t' read -r id active events_ok ctype_ok ssl_ok missing extra; do
    [[ -n "$id" ]] || continue
    if [[ "$active" == "yes" && "$events_ok" == "yes" && "$ctype_ok" == "yes" && "$ssl_ok" == "yes" ]]; then
      # Any fully configured hook wins, even if another URL match drifts.
      HOOK_ID="$id"
      HOOK_DRIFT=""
      return 0
    fi
    if [[ -z "$HOOK_ID" ]]; then
      HOOK_ID="$id"
      drift=""
      [[ "$active" == "yes" ]] || drift+="${drift:+, }inactive"
      if [[ "$events_ok" != "yes" ]]; then
        # Name what deviates from the exact required set, so the operator
        # sees WHY a superset hook still counts as drift.
        ev_detail=""
        [[ -n "$missing" && "$missing" != "-" ]] && ev_detail+="missing: $missing"
        [[ -n "$extra" && "$extra" != "-" ]] && ev_detail+="${ev_detail:+; }extra: $extra"
        drift+="${drift:+, }events not the exact required set${ev_detail:+ ($ev_detail)}"
      fi
      [[ "$ctype_ok" == "yes" ]] || drift+="${drift:+, }content_type not json"
      [[ "$ssl_ok" == "yes" ]] || drift+="${drift:+, }insecure_ssl enabled"
      HOOK_DRIFT="$drift"
    fi
  done <<< "$records"
  return 3
}

# Full desired-state body, shared by create (POST) and repair (PATCH) —
# both re-assert the same state, so drift can never survive an apply. On
# PATCH, GitHub replaces the "events" list wholesale with exactly the three
# events below, so a superset hook is trimmed back to the desired set.
# GitHub ignores the extra "name" field on PATCH. JSON string escaping:
# backslash and double-quote are the only characters in a URL-shaped value
# that need it, which keeps this dependency-free.
webhook_payload() {
  local url_json
  url_json="${WEBHOOK_URL//\\/\\\\}"
  url_json="${url_json//\"/\\\"}"
  cat << EOF
{
  "name": "web",
  "active": true,
  "events": ["pull_request", "issue_comment", "pull_request_review"],
  "config": {
    "url": "$url_json",
    "content_type": "json",
    "insecure_ssl": "0"
  }
}
EOF
}

# Create the webhook at the given API path (orgs/<org>/hooks or
# repos/<owner>/<repo>/hooks). The request body is fed to gh via stdin
# (--input -) so the webhook URL — a bearer credential — never appears on a
# command line, where any local process could read it out of argv via ps.
# Success stdout (the full hook JSON, which echoes config.url back) is
# discarded; failure stderr is logged with every occurrence of the webhook
# URL replaced by its redacted form.
create_hook() {
  local api_path="$1" err rc=0
  err="$({ webhook_payload | gh api "$api_path" --method POST --input - > /dev/null; } 2>&1)" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    log "  [warn] hook create failed for $api_path: ${err//"$WEBHOOK_URL"/$MASKED_WEBHOOK_URL}"
  fi
  return "$rc"
}

# Repair a drifted hook in place: PATCH re-asserts the full desired state
# (active, events, content_type, insecure_ssl — and the URL, which the
# config object must always carry). Only ever called for a hook that
# already points at the Multica webhook URL; other services' hooks are
# never touched. Same stdin + redaction hygiene as create_hook.
update_hook() {
  local api_path="$1" hook_id="$2" err rc=0
  err="$({ webhook_payload | gh api "$api_path/$hook_id" --method PATCH --input - > /dev/null; } 2>&1)" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    log "  [warn] hook update failed for $api_path/$hook_id: ${err//"$WEBHOOK_URL"/$MASKED_WEBHOOK_URL}"
  fi
  return "$rc"
}

# ---------- Summary bookkeeping ----------

SUMMARY_ROWS=()
CREATED=0
UPDATED=0
PLANNED=0
PLANNED_UPDATES=0
SKIPPED=0
WARNED=0
FAILED=0

add_row() { # target kind action detail
  SUMMARY_ROWS+=("$(printf '%s\t%s\t%s\t%s' "$1" "$2" "$3" "$4")")
  case "$3" in
    created) CREATED=$((CREATED + 1)) ;;
    updated) UPDATED=$((UPDATED + 1)) ;;
    would-create) PLANNED=$((PLANNED + 1)) ;;
    would-update) PLANNED_UPDATES=$((PLANNED_UPDATES + 1)) ;;
    skip) SKIPPED=$((SKIPPED + 1)) ;;
    warn) WARNED=$((WARNED + 1)) ;;
    fail) FAILED=$((FAILED + 1)) ;;
  esac
}

# ---------- Hook installation ----------

ensure_hook() { # target api_path kind
  local target="$1" api_path="$2" kind="$3" rc=0
  hook_state "$api_path" || rc=$?
  case "$rc" in
    0)
      log "[$target] hook already installed with the desired config — skip"
      add_row "$target" "$kind" "skip" "installed (url, active, exact events, content_type, insecure_ssl all match)"
      ;;
    1)
      if [[ "$APPLY" -eq 1 ]]; then
        log "[$target] creating $kind (events: $EVENTS_HUMAN; content_type: json)"
        if create_hook "$api_path"; then
          add_row "$target" "$kind" "created" "events: $EVENTS_HUMAN"
        else
          add_row "$target" "$kind" "fail" "create rejected (missing admin:org_hook / admin:repo_hook scope?)"
        fi
      else
        log "[$target] would create $kind (events: $EVENTS_HUMAN; content_type: json)"
        add_row "$target" "$kind" "would-create" "events: $EVENTS_HUMAN"
      fi
      ;;
    3)
      if [[ "$APPLY" -eq 1 ]]; then
        log "[$target] hook points at the Multica webhook URL but config drifted ($HOOK_DRIFT) — repairing"
        if update_hook "$api_path" "$HOOK_ID"; then
          add_row "$target" "$kind" "updated" "repaired drift: $HOOK_DRIFT"
        else
          add_row "$target" "$kind" "fail" "update rejected (missing admin:org_hook / admin:repo_hook scope?)"
        fi
      else
        log "[$target] hook points at the Multica webhook URL but config drifted ($HOOK_DRIFT) — would update"
        add_row "$target" "$kind" "would-update" "config drift: $HOOK_DRIFT"
      fi
      ;;
    *)
      log "[$target] cannot list existing hooks — refusing to create blind"
      add_row "$target" "$kind" "fail" "hook listing failed (need admin on target); state unknown, not creating"
      ;;
  esac
}

process_owner() {
  local owner="$1" otype repos repo repo_count
  if ! otype="$(owner_type "$owner")" || [[ -z "$otype" ]]; then
    add_row "$owner" "owner" "fail" "cannot resolve via gh api users/<owner> (typo? token visibility?)"
    return 0
  fi

  if [[ "$otype" == "Organization" ]]; then
    if org_admin "$owner"; then
      ensure_hook "$owner" "orgs/$owner/hooks" "org-hook"
      return 0
    fi
    log "[$owner] org, but caller is not an active admin — falling back to per-repo hooks"
  fi

  if ! repos="$(list_owner_repos "$owner")"; then
    add_row "$owner" "repos" "fail" "cannot enumerate repositories (gh repo list failed)"
    return 0
  fi
  if [[ -z "$repos" ]]; then
    add_row "$owner" "repos" "skip" "no non-archived repositories visible to this token"
    return 0
  fi
  # gh repo list stops at --limit with no truncation marker: hitting the
  # limit means repos beyond it were silently dropped from this run. Flag it
  # loudly instead of letting the coverage gap pass unnoticed.
  repo_count="$(printf '%s\n' "$repos" | grep -c . || true)"
  if [[ "$repo_count" -ge "$REPO_LIST_LIMIT" ]]; then
    log "[$owner] repo listing hit the $REPO_LIST_LIMIT-repo limit — repos beyond it are NOT covered by this run"
    add_row "$owner" "repos" "warn" "listing truncated at $REPO_LIST_LIMIT repos; coverage incomplete — raise REPO_LIST_LIMIT or split the scope"
  fi
  while IFS= read -r repo; do
    [[ -z "$repo" ]] && continue
    ensure_hook "$owner/$repo" "repos/$owner/$repo/hooks" "repo-hook"
  done <<< "$repos"
}

# ---------- Main ----------

if [[ "$APPLY" -eq 1 ]]; then
  log "APPLY mode: webhooks will be created on GitHub."
else
  log "DRY RUN (read-only API calls; no hooks created). Re-run with --apply to execute."
fi
log "Webhook target: $MASKED_WEBHOOK_URL"
log ""

while IFS= read -r owner; do
  [[ -z "$owner" ]] && continue
  process_owner "$owner"
done <<< "$OWNERS"

# ---------- Summary table ----------

log ""
log "Summary:"
if [[ "${#SUMMARY_ROWS[@]}" -gt 0 ]]; then
  {
    printf 'TARGET\tKIND\tACTION\tDETAIL\n'
    printf '%s\n' "${SUMMARY_ROWS[@]}"
  } | render_table
fi

log ""
if [[ "$APPLY" -eq 1 ]]; then
  log "[summary] created=$CREATED updated=$UPDATED skipped=$SKIPPED warned=$WARNED failed=$FAILED"
else
  log "[summary] would-create=$PLANNED would-update=$PLANNED_UPDATES skipped=$SKIPPED warned=$WARNED failed=$FAILED (dry run)"
  [[ "$((PLANNED + PLANNED_UPDATES))" -gt 0 ]] && log "Re-run with --apply to apply the plan above."
fi

if [[ "$WARNED" -gt 0 ]]; then
  log "warning: $WARNED warning row(s) above — coverage may be incomplete."
fi

if [[ "$FAILED" -gt 0 ]]; then
  die "$FAILED target(s) failed — see rows above. Nothing was created blind; fix access/scopes and re-run."
fi
