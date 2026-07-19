---
name: sync-multica
description: Safely synchronize this repository's company constitution, Profession Profiles, Agent Instances, and persistent Squad topology to Multica, then prove the deployed state converges.
---

# Sync Multica

Treat the repository as desired state and Multica as deployed state. Plan first, write only after explicit authorization, and prove convergence with a fresh read.

## Safety Contract

- Run from this repository's root.
- Require `AGENTS.md` and `CLAUDE.md` to be byte-identical.
- Never commit workspace IDs, agent IDs, mention links, tokens, runtime IDs, or private environment values.
- Resolve deployment identity from `deployments/agents.json` logical names and current remote reads. Never guess an ambiguous agent, runtime, skill, or Squad.
- Never automatically archive an agent or Squad or remove an extra Squad member. Report the drift and require a separately reviewed destructive migration.
- Apply only from a clean `main` whose `HEAD` equals `origin/main`.
- Redact tokens and UUIDs from reported evidence. Agent, runtime-provider, workspace, and Squad names are acceptable.

## Managed State

| Source | Multica state |
|---|---|
| `workspace-context.md` | Workspace context |
| `agents/<profession>/personality.md` | Agent instructions |
| `agents/<profession>/skill.md` | Profession skill content and attachments |
| `deployments/agents.json` | Logical instance name, profession, runtime provider, and model intent |
| `squads/*/squad.json` | Squad name, description, leader, membership, and squad-local roles |
| `squads/*/instructions.md` | Squad instructions |

The two reconcilers are intentionally separated:

- `scripts/sync-topology.py` resolves instances and persistent Squads. It may create only instances marked `create_if_missing` and missing tracked Squads; it does not delete or prune.
- `scripts/sync-multica.sh` synchronizes company context and Profession Profile content for already-resolved instances.

## Workflow

1. Validate the checkout and files:

   ```bash
   git fetch origin main
   test "$(git branch --show-current)" = main
   test -z "$(git status --porcelain)"
   test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
   cmp -s AGENTS.md CLAUDE.md
   tests/sync-topology.test.py
   tests/sync-multica.test.sh
   bash tests/pr-sweep.test.sh
   ```

2. Confirm the selected target using fresh reads:

   ```bash
   multica --version
   multica auth status
   multica workspace get --output json
   multica runtime list --output json
   multica agent list --output json
   multica squad list --output json
   ```

   When `MULTICA_WORKSPACE_ID` is set, require it to match the selected workspace. Report the workspace name before the first apply in the conversation.

   If more than one online runtime exposes a required provider, set a shell-local exact mapping such as `SYNC_RUNTIME_CLAUDE`, `SYNC_RUNTIME_CODEX`, or `SYNC_RUNTIME_GROK` to one runtime name or ID. Likewise, map existing personal server display names with `SYNC_AGENT_<LOGICAL_ID>` variables such as `SYNC_AGENT_ENGINEER_A`; never persist either mapping.

3. Run both read-only plans:

   ```bash
   scripts/sync-topology.py
   scripts/sync-multica.sh
   ```

   Review every row. Missing non-creatable instances, ambiguous resources, multiple online runtimes for the same provider, extra Squad members, or unexpected new resources are blockers.

4. Apply topology first, then content:

   ```bash
   scripts/sync-topology.py --apply
   scripts/sync-multica.sh --apply
   ```

5. Perform a fresh verification after both apply processes finish:

   ```bash
   scripts/sync-topology.py --verify
   scripts/sync-multica.sh --verify
   ```

   Success requires both exit statuses to be zero and no remaining drift.

6. For the first shared-instance rollout, run a non-production canary Issue before assigning real work:

   - The same agent can belong to Discovery and Experience.
   - Removing it from the canary does not mutate another Squad.
   - The leader sees the correct Squad instructions and only the originating roster.
   - A member's mention-free delivery returns to the correct leader run.
   - Squad activity is attributed to the originating Squad.
   - No unrelated Project or Domain context leaks into the run.
   - Evaluator-A and Evaluator-B never verify their own work and receive independent pre-verdict contexts.

7. Report concise evidence:

   - local `HEAD` and `origin/main` equality;
   - Multica CLI version and workspace name;
   - created/updated instances, skills, and Squads by logical name, without UUIDs;
   - final topology and content verify exit statuses;
   - canary result and anything skipped.

## Scope Boundary

This skill manages only the tracked, non-secret desired state above. Agent archives, Squad archives, membership removals, runtime installation, secrets, project resources, autopilots, publishing, deployments, and external sends require separate explicit authorization.
