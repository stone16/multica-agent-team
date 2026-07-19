---
name: sync-multica
description: Safely synchronize this repository's desired state to Multica and prove the remote state matches. Use when workspace-context.md, agents/*/personality.md, agents/*/skill.md, roster mappings, or the Multica workspace configuration changed; when bootstrapping or repairing the server-side agent team; or when asked to plan, apply, audit, or verify a Multica sync from this repo.
---

# Sync Multica

Treat the repository as desired state and the Multica server as deployed state. Always plan first, write only with explicit authorization, then prove convergence with a fresh read.

## Safety contract

- Run from this repository's root.
- Never commit workspace IDs, agent IDs, mention links, tokens, private repository names, or runtime IDs.
- Keep operational mappings in the current shell environment with `SYNC_AGENT_<ROLE>` / `SYNC_SKILL_<ROLE>`.
- Fail closed on an unmapped or ambiguous agent. Never guess which person, runtime, or computer owns a role.
- Never create, rename, archive, or rebind an agent or squad as part of this skill. Those topology changes require a separately reviewed migration plan.
- Never apply from a dirty tree, a non-`main` branch, or a `main` that is behind `origin/main`.
- Redact tokens and environment values from evidence. Agent and workspace names are acceptable; UUIDs are operational identity and should be summarized, not pasted.

## Workflow

1. Confirm the checkout is safe:

   ```bash
   git status --short --branch
   git fetch origin main
   test "$(git branch --show-current)" = main
   test -z "$(git status --porcelain)"
   test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
   ```

   If any check fails, stop. Do not switch branches, discard changes, merge, or rebase without the user's authorization.

2. Confirm the CLI and target:

   ```bash
   multica --version
   multica auth status
   multica workspace get --output json
   ```

   When `MULTICA_WORKSPACE_ID` is set, require it to match the workspace returned by the CLI. When it is unset, report the selected workspace name and ask for confirmation before the first apply in the conversation.

3. Resolve agent mappings without guessing. The defaults expect server agents named `CEO`, `PM`, `Designer`, `Engineer-A`, `Engineer-B`, `GTM`, `Evaluator`, and `Researcher`. If the server uses different names, export mappings only for this shell:

   ```bash
   export SYNC_AGENT_CEO='<server-name-or-id>'
   export SYNC_AGENT_PM='<server-name-or-id>'
   export SYNC_AGENT_DESIGNER='<server-name-or-id>'
   export SYNC_AGENT_ENGINEER='<engineer-a-name-or-id>,<engineer-b-name-or-id>'
   export SYNC_AGENT_GTM='<server-name-or-id>'
   export SYNC_AGENT_EVALUATOR='<server-name-or-id>'
   export SYNC_AGENT_RESEARCHER='<server-name-or-id>'
   ```

   Do not persist these values in tracked files.

4. Run the read-only plan:

   ```bash
   scripts/sync-multica.sh
   ```

   Review every row. The plan covers workspace context, skill content, agent instructions, and skill-to-agent assignments. Any `unmapped`, `failed`, or unexpected create is a blocker.

5. Apply only after the user has authorized the displayed plan:

   ```bash
   scripts/sync-multica.sh --apply
   ```

6. Verify using a new server read, never the apply process's cached state:

   ```bash
   scripts/sync-multica.sh --verify
   ```

   Success requires exit status 0 and every managed row to be `up-to-date` or `attached`. A verify run with any missing resource, content drift, instruction drift, attachment drift, read failure, or unmapped target must exit nonzero.

7. Report concise evidence:

   - local `HEAD` and `origin/main` equality;
   - Multica CLI version and workspace name;
   - counts of updated/created/attached resources from apply;
   - the final verify exit status and summary;
   - any topology work intentionally left out.

## Scope boundary

This skill synchronizes content and attachments for agents that already exist. Agent creation, runtime/model changes, renames, archives, squad creation/membership, project resources, and autopilots are separate topology migrations because a wrong choice can route work to the wrong computer or identity.
