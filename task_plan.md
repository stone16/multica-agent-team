# Task Plan: Portable Multica Gateway and Runtime Foundation

## Goal

Define and then implement the smallest portable foundation that can take a project from evidence-backed discovery through product definition, implementation, independent evaluation, and end-to-end verification on Multica, while keeping merge, deployment, production writes, and external publication behind explicit human gates.

## Target

- Repository: `/Users/leilei/dev/personal/agent-team`
- Baseline: `main@584d7b6`
- Comparison source: `/Users/leilei/dev/work/crm-skill-plugin/agent-team@683159a`
- Working branch: `feat/agent-team-runtime-foundation-plan`

## Current Phase

Phase 3 — Implementation (Gateway slice)

## Definition of Done for this planning slice

- The migration boundary is backed by `file:line` evidence from both repositories.
- The first implementation slice has explicit scope, non-goals, acceptance criteria, and verification commands.
- Runtime identity and secret-handling rules are explicit before any Multica apply is considered.
- No private CRM identifiers, URLs, tokens, owner IDs, or runtime IDs are copied into the public repository.

## Phases

### Phase 1: Requirements & Discovery

- [x] Confirm target repository, ref, and clean starting state
- [x] Compare the generic repository with the rebased CRM `agent-team/` implementation
- [x] Identify reusable Gateway, runtime-capability, host-pool, and E2E patterns
- [x] Record evidence and migration risks in `findings.md`
- **Status:** complete

### Phase 2: Planning & Structure

- [x] Choose the smallest first vertical slice
- [x] Separate portable contracts from CRM-private deployment overlays
- [x] Define acceptance criteria and verification commands
- [x] Record rejected alternatives and their constraints
- **Status:** complete

### Phase 3: Implementation

- [x] PR 1 slice: add a generic Gateway contract and deterministic handler boundary
- [x] PR 2 slice: add a portable transient-retry decision contract
- [ ] PR 2 follow-up: add a portable runtime-capability manifest and validator/installer contract
- [ ] PR 3: add host-pool logical bindings with fail-closed identity validation
- [ ] PR 4: add Initiative-level controller/state transitions only after the first three converge
- **Status:** in progress — Gateway and retry slices implemented locally; delivery still requires review and an isolated PR.

### Phase 4: Testing & Verification

- [ ] Add red tests for each new deterministic rule before implementation
- [ ] Run existing topology, Multica sync, and PR-sweep suites after each PR
- [ ] Run a synthetic/public vertical slice through discovery → experience → delivery → evaluator → E2E
- [ ] Re-read remote state after any authorized canary apply
- **Status:** pending

### Phase 5: Delivery

- [ ] Open one ready-for-review PR per atomic slice with required evidence
- [ ] Obtain independent Evaluator verdicts for user-visible behavior
- [ ] Keep merge, deploy, production mutation, and external publication as human gates
- **Status:** pending

## Accepted Choice

Implement in this order: Gateway → runtime-capability contract → host-pool validation → one low-risk synthetic vertical slice → Initiative Controller.

## Rejected Alternatives

- Copy the CRM `agent-team/` directory wholesale — rejected because it includes MoeGo-specific professions, Skills, URLs, workspace identity, owner identity, and runtime identity that are not portable.
- Build the full cross-lifecycle controller first — rejected because current state is carried by native Multica Issues/comments/assignments and the auto-harness is still primarily a protocol; a controller before ingress and runtime convergence would multiply failure modes.
- Make the Gateway perform worker work — rejected because deterministic routing should remain a small deep module, while implementation, research, design, and evaluation belong to the routed Squad members.
- Store runtime IDs, owner IDs, workspace IDs, or secret values in the public manifest — rejected because repository invariants require logical identities in Git and operational identity in private overlays/environment.

## Constraint

The first slice must prove a trustworthy request-to-verified-result path without leaking private deployment identity or bypassing the existing Orchestrator-led DoD and human exit gates.

## Key Questions

1. Which first synthetic/public project will exercise Discovery → Experience → Delivery without customer or production data?
2. Will private deployment overlays be supplied as ignored `.local` files, CI environment variables, or both?
3. Which Multica workspace/runtime is authorized for a canary, and who owns the human apply/merge gate?

## Verification Commands

Baseline and repository checks:

```bash
python3 tests/sync-topology.test.py
bash tests/sync-multica.test.sh
bash tests/pr-sweep.test.sh
cmp -s AGENTS.md CLAUDE.md
```

For each implementation PR, add focused tests that fail without the change. For any authorized canary, run a dry-run/plan first, then apply only from a clean `main == origin/main`, and finish with a fresh verify plus the affected path from `E2E-RUNBOOK.md`.

## Errors Encountered

| Error | Attempt | Resolution |
|---|---:|---|
| Generic repository has no root `ENGINEERING.md` or `OPINIONS.md` | 1 | Read the runtime-authoritative copies at `/Users/leilei/.codex/ENGINEERING.md` and `/Users/leilei/.codex/OPINIONS.md` |

## Notes

- Do not call Multica apply from this feature branch. The repository explicitly requires clean `main == origin/main` for non-experimental topology application.
- The next code change should be a single atomic Gateway PR, not a combined migration of all CRM internals.
- Gateway slice files: `scripts/gateway.py`, `policies/routing.json`, and `tests/test_gateway.py`.
- The slice is a pure adapter boundary: it has no Multica credentials, live URLs, runtime IDs, or
  network client. A production adapter and a canary remain separate follow-up work.
- Retry policy slice: `scripts/retry_policy.py` and its contract tests. It schedules, but does not
  execute, a retry at least 30 minutes after a timeout/503-class failure; the caller must re-read
  the Issue and suppress duplicate work when an active run exists.
