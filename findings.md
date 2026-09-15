# Findings & Decisions

## Requirements

- Reuse the CRM implementation's Gateway, runtime capability, host-pool, and E2E patterns in the public `agent-team` repository.
- Achieve an end-to-end Multica flow: early research → product definition/design → implementation → independent testing/evaluation → verified PR.
- Keep deterministic routing, retries, validation, counting, sorting, and status transitions in code; keep ambiguous research/design/evaluation judgment in agents.
- Preserve human gates for merge, deploy, production/customer-data writes, and external publication.

## Research Findings

### Generic repository baseline

- The public repository defines seven Profession Profiles, nine intended Agent Instances, and five persistent Squads; the Orchestrator selects the smallest sufficient roster per run (`README.md:19-27`).
- Its run protocol already separates Issue-scoped context, DoD-bearing delegation, mention-free deliveries, independent Evaluator verification, and closure (`README.md:40-48`).
- Its deployment manifest currently contains only logical agents/provider/model intent; it has no standalone Gateway, runtime-capability manifest, or host-pool manifest (`deployments/agents.json:1-61`).
- Squad manifests declare `handoff_targets`, but the current generic code does not consume those targets as an Initiative-level state machine; this is a later controller concern (`squads/discovery/squad.json:1-21`, `squads/experience/squad.json:1-22`, `squads/delivery/squad.json:1-20`).
- The auto-harness defines checkpoint, E2E, and retro protocol in the Engineer/Orchestrator prompts, but child creation and transition execution remain Multica-native orchestration behavior rather than a repository controller (`templates/auto-harness.md:92-221`, `agents/orchestrator/skill.md:37-49`).

### CRM implementation worth extracting

- Gateway input is a small structured request `{user_text, intent}`; the model supplies intent while code performs deterministic target lookup and Issue mutation (`agent-team/skills/routing-contract/scripts/gateway.py:90-98`, `:171-220`).
- Gateway safety is explicit: task attribution is required, Multica output must be JSON, target names must resolve uniquely, and failed operations return a bounded error (`agent-team/skills/routing-contract/scripts/gateway.py:25-70`).
- Gateway control operations distinguish `status`, `continue`, and `retry`; `continue` adds one same-Issue comment to the current assignee and `retry` reruns the Issue (`agent-team/skills/routing-contract/scripts/gateway.py:138-168`).
- The routing policy is intentionally small and maps mission intents to Squad targets, keeping model judgment separate from deterministic dispatch (`agent-team/policies/routing.json:1-9`).
- Runtime capabilities are declared by pinned source revision and capability names, with a materialization step that verifies the checkout and declared Skills (`agent-team/deployments/runtime-capabilities.json:1-56`, `agent-team/README.md:68-79`).
- Host-pool resolution checks logical pool uniqueness and exact runtime name, provider, runtime ID, workspace ID, and owner ID, then requires online status; display name alone is insufficient (`agent-team/scripts/sync.py:133-164`).
- Runtime identity is also validated for direct member-default bindings, rejecting workspace/owner mismatches and offline runtimes (`agent-team/scripts/sync.py:167-190`).
- The CRM onboarding path proves the intended operational sequence: validate, unit tests, dry-run plan, deliberate experimental canary only when authorized, then fresh verification (`agent-team/ONBOARDING.md:148-165`).
- The CRM runbook treats the E2E path as a separate verification surface rather than assuming topology convergence proves hosted behavior (`agent-team/README.md:180-199`, `agent-team/E2E-RUNBOOK.md:1-47`).

### Non-portable CRM details

- The CRM Gateway and agents are tied to MoeGo/CRM descriptions, CRM Issue identifiers, a CRM issue URL, and CRM-specific Skill names (`agent-team/skills/routing-contract/scripts/gateway.py:16-18`, `agent-team/policies/routing.json:2-9`, `agent-team/deployments/agents.json:1-44`).
- The CRM host-pool manifest includes live runtime, workspace, and owner UUIDs (`agent-team/deployments/host-pools.json:1-11`); these must become private overlay data in the public repository.
- The CRM runtime-capability manifest names MoeGo private Skills and a private plugin repository (`agent-team/deployments/runtime-capabilities.json:1-56`); the generic repository should define a schema and inject project-specific capabilities privately.

## Technical Decisions

| Decision | Rationale |
|---|---|
| Start with a generic Gateway PR | It is the smallest user-visible seam and proves intent → target → Issue without requiring a new controller or private runtime data. |
| Keep Gateway as an adapter over native Multica Issue operations | Native Issues/comments/assignments are already the durable run surface; a second database would create competing state. |
| Use a schema-first capability manifest | Skill/runtime/MCP/env declarations need reviewable versions and validation, while secret values remain out of Git. |
| Represent host pools by logical IDs in public Git and resolve exact identities from a private overlay | This preserves reproducibility and fail-closed identity checks without publishing operational identifiers. |
| Defer Initiative Controller until three foundations converge | A controller would otherwise encode unproven ingress/runtime assumptions and duplicate native Issue state. |

## Issues Encountered

| Issue | Resolution |
|---|---|
| CRM nested `agent-team/` is far ahead of the public repository and contains private deployment data | Treat it as a reference implementation, extract interfaces and tests, and rewrite manifests with neutral logical identities. |
| Public repository has no single Initiative state model | Use native Issue state for the first slice; design an Initiative Controller only after Gateway/runtime/host-pool evidence exists. |

## Resources

- Generic target: `/Users/leilei/dev/personal/agent-team`
- CRM comparison source: `/Users/leilei/dev/work/crm-skill-plugin/agent-team`
- Generic operating model: `docs/operating-model.md`
- Generic run protocol: `workspace-context.md:79-100`
- CRM Gateway implementation: `/Users/leilei/dev/work/crm-skill-plugin/agent-team/skills/routing-contract/scripts/gateway.py`
- CRM runtime resolver: `/Users/leilei/dev/work/crm-skill-plugin/agent-team/scripts/sync.py:133-190`
- CRM E2E runbook: `/Users/leilei/dev/work/crm-skill-plugin/agent-team/E2E-RUNBOOK.md`

## Visual/Browser Findings

- No browser or external web source was used. All findings are from local repository files and command output.

## LoopX comparison (2026-09-14)

LoopX is an external, provider-neutral control plane rather than an execution runtime. Its public contract keeps durable objective, todos, gates, evidence, quota, recovery, and handoffs visible while Codex/Claude/other harnesses execute one bounded slice. It explicitly keeps production writes and final ownership behind human gates. Source: https://github.com/huangruiteng/loopx (README, architecture and runtime sections).

The portable repository currently has deterministic ingress (`scripts/gateway.py`) and transient retry decisions (`scripts/retry_policy.py`), but no durable receipt schema, metrics event boundary, promotion state machine, or rollback evidence contract. The CRM implementation supplies reusable patterns for exact identity/readiness checks, fail-closed failover plans, per-originator fairness, overload receipts, and p50/p95/p99 hosted evidence. Its production scheduler and lease controller remain outside the repository, so those patterns should be adapted as interfaces rather than copied wholesale.

Adaptation decision: keep Multica Issue/Task as the durable execution record; add provider-neutral receipt and metrics contracts with open extension fields; model promotion and rollback as explicit, idempotent state transitions; leave deployment adapters and credentials to CI/private overlays. LoopX concepts map to these contracts as goal/run identity, bounded attempt, gate, evidence, quota, and handoff, without importing LoopX code or making it the production controller.
