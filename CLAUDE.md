# Company Operating System

This repository is the source of truth for the reusable agent company deployed to Multica. These rules apply regardless of whether Claude, Codex, Grok, or another model edits or executes the repository.

`AGENTS.md` and `CLAUDE.md` are intentionally byte-identical mirrors. Edit both in the same change and verify with `cmp -s AGENTS.md CLAUDE.md`. Neither file is an adapter for one runtime.

## Source of Truth

Use this precedence when facts conflict:

1. The user's explicit instruction for the current task.
2. `AGENTS.md` and `CLAUDE.md`, which must say the same thing.
3. `workspace-context.md` for company-wide Multica behavior.
4. `squads/*/squad.json` and `squads/*/instructions.md` for a functional Squad.
5. `agents/<profession>/personality.md` and `agents/<profession>/skill.md` for stable professional capability.
6. The current Project ledger and Issue Definition of Done for domain and run context.
7. `README.md` for human onboarding.

Do not silently blend conflicting rules. Follow the higher source, state the conflict, and flag the lower source for correction.

## Company Ontology

Keep these objects separate:

- **Profession Profile**: stable, domain-neutral responsibility, judgment, tools, evidence contract, and prohibited work. It lives under `agents/<profession>/`.
- **Agent Instance**: a deployed identity with one primary Profession Profile, runtime/model, permissions, and capacity. Multiple instances may share one profile.
- **Squad Definition**: a long-lived functional routing and operating contract. It has a leader, members, squad-local roles, activation rules, workflow, and entry/exit artifacts.
- **Squad Run**: one bounded Issue, project phase, incident, or objective. Run state is fresh by default.
- **Project or Domain Ledger**: durable facts, evidence, decisions, PRDs, designs, code, evaluations, and incident records for one business domain.

Long-lived Squad identity does not authorize long-lived unreviewed conversation memory. Promote reviewed facts and decisions to a ledger; do not treat logs, traces, metrics, or chat history as durable product state.

## Profession and Instance Topology

The company keeps seven reusable Profession Profiles:

| Profession | Stable responsibility | Deployment intent |
|---|---|---|
| Orchestrator | Own the objective, compose the smallest sufficient team, dispatch with a DoD, verify, and close | Claude runtime; one `claude-opus-5` instance initially |
| PM | Define user value, scope, PRDs, acceptance criteria, and product decisions | Claude runtime |
| Designer | Define journeys, interactions, prototypes, and experience-quality decisions | Claude runtime |
| Engineer | Design and implement correct, observable, reversible systems | Two Codex instances: Engineer-A and Engineer-B; both `gpt-5.6-sol` |
| GTM | Positioning, launch, channel experiments, growth, and market feedback | Grok runtime default |
| Evaluator | Independent behavioral, security, performance, and DoD verification | Two Grok runtime-default instances: Evaluator-A and Evaluator-B |
| Researcher | Primary-source evidence, market/user/technical research, and uncertainty reduction | Claude runtime |

Two instances sharing a profile are independent execution lanes, not new professions. Add a new Profession Profile only when a repeated responsibility has a materially different evidence contract, tool or permission boundary, or decision authority.

## Persistent Squads

Maintain these five baseline Multica Squad objects:

| Squad | Mission | Canonical definition |
|---|---|---|
| Discovery | Establish an evidence-backed target user, problem, opportunity, and positioning hypothesis | `squads/discovery/` |
| Experience | Turn a validated problem into a coherent journey and testable product definition | `squads/experience/` |
| Delivery | Convert an accepted product definition into verified, shippable behavior | `squads/delivery/` |
| Growth | Launch the product and improve acquisition, activation, retention, and commercial learning | `squads/growth/` |
| Reliability | Maintain reliability, safety, incident response, and product health | `squads/reliability/` |

Assign complex or multi-role work to one exact owning Squad by UUID, not to several individual agents. Squad membership is a capability roster, not an instruction to activate everybody. For every run, the Orchestrator selects the smallest sufficient set of roles and states the distinct output expected from each activated member.

An Issue has exactly one owning Squad at a time, and its body uses `templates/squad-issue.md` as the execution and result contract. Other Squads may be consulted through a bounded child Issue or an artifact-backed mention that states the exact question and return artifact. Transfer ownership only through an artifact-backed handoff with acceptance criteria; do not make `Discovery -> Experience -> Delivery -> Growth -> Reliability` an automatic waterfall.

A direct-agent fast path is allowed only when work is genuinely trivial, single-owner, low-risk, has no cross-profession dependency, and needs no independent gate. The first unmet condition requires Squad assignment. Do not fan one complex goal out to several agents from an external caller; assign the owning Squad and let its leader compose the lanes.

**PR-sweep compatibility exception.** The checked-in PR-sweep automation may reuse one dedicated, serialized review issue and assign it directly, one lane at a time, to the non-author Engineer, Evaluator, and Orchestrator. This exception exists only because `.github/scripts/pr-sweep.sh` deterministically preserves one issue identity, review-lane order, immutable head SHA, Orchestrator-routed rework, and the full result → metadata → activity → status close sequence; it is not a general external-caller bypass. No other complex or multi-role flow may fan work out through direct assignment.

No fallback identity is live merely because a repository field names one. A fallback is eligible only when it is a separate Orchestrator identity, deployed and added to every affected Squad, and a fresh topology verify proves that exact topology. Until then, reruns stay with the current Squad leader and sustained provider/runtime entry failures escalate to the human with evidence. Never advertise or route to an unverified fallback.

Keep one accountable initiative owner and one Project ledger across Squad transitions. If phase handoffs become the dominant source of rework for a mature product, create a domain/value-stream Squad that owns that product across its lifecycle while retaining the functional Squads as specialist capability pools.

## Conditional Squads

Do not create speculative Squads. A candidate graduates into a persistent Squad only when all are true:

1. The responsibility recurs across at least three real runs or has a non-negotiable independent permission boundary.
2. It needs a stable multi-profession roster and routing target, not just one specialist or one skill.
3. Its entry, exit, and evidence contract differ materially from an existing Squad.
4. The expected reduction in queueing, handoff rework, or risk is worth the added orchestration cost.

Candidates include:

- **Domain / Value Stream**: when one mature product needs end-to-end outcome ownership across lifecycle phases.
- **Strategy & Portfolio**: when multiple concurrent ventures need recurring capital allocation and kill/continue decisions.
- **Platform & Enablement**: when three or more product streams repeatedly depend on the same internal platform or developer capability.
- **Security, Trust & Compliance**: when regulation, access separation, or a recurring security queue requires independent authority.
- **Complicated Subsystem**: when a specialized technical domain cannot be safely served by the general Engineer profile.

Evaluation remains an independent cross-Squad service and gate, not a Squad, until it develops its own sustained backlog and multi-profession workflow. Incident Response remains a Reliability operating mode. Legal, finance, data analysis, and content remain skills or specialists until they meet the graduation test.

## Run Protocol

Run behavior is composed from:

```text
company contract
+ current Squad contract
+ Project / Domain ledger
+ current Issue and Definition of Done
```

For each multi-step run:

1. Confirm the Issue is assigned to its exact owning Squad. Read the Issue contract, relevant ledger artifacts, current Squad roster, Squad instructions, and threaded/system comments.
2. State the objective, assumptions, risks, and acceptance criteria.
3. Plan the minimum necessary role activations. Use deterministic code for routing, retries, validation, counting, sorting, and status transitions; use models for decomposition, ambiguous judgment, research, design, synthesis, and evaluation.
4. Dispatch one bounded contract at a time with:

   ```yaml
   dod:
     outcome: <observable state that counts as done>
     evidence: <tests, screenshots, links, measurements, or cited artifacts>
     verification: self | evaluator | dual_evaluator | human
     max_rounds: 2
   ```

5. A member returns a mention-free delivery addressing every evidence item. The current Squad leader verifies it and chooses the next transition.
6. Use one Evaluator for ordinary independent verification. Use both Evaluators only for high-risk, irreversible, security-sensitive, or explicitly dual-lens work. They receive independent pre-verdict contexts and do not coordinate until both verdicts exist.
7. Close only when the acceptance criteria are evidenced. Post one consolidated parent result, index it with the required result metadata, record Squad activity, and only then change parent status. Promote durable results to the Project ledger and record unresolved risks explicitly.

Only the current Squad leader may `@`-mention Squad members, and only for delegation. Members never route work by mention. A member's mention-free delivery returns control to the leader. Protocol identifiers such as `CEO_MENTION` or `ceo-resolved` may remain in automation for compatibility; they refer to the Orchestrator role.

## Native Staged Child Work

Use native child issues when work has dependencies, independent acceptance, its own retry or cancellation boundary, or needs a queryable work graph. Create Stage 1 children with `--stage 1 --status todo`; create later-stage children with `--stage N --status backlog`. Same-stage work may run in parallel.

Only `done` and `cancelled` close a stage barrier. `blocked` keeps the frontier open. A native barrier wake notifies the parent assignee but does not promote later backlog children; the leader reads `multica issue children <parent>`, verifies dependencies, and promotes only the newly eligible children to `todo`.

Use same-parent comment fan-out only for small, short, context-sharing analyses that do not need independent lifecycle visibility. Do not hand-count child completion in plan comments when native stages represent the dependency graph.

## Deterministic Result and Recovery Contract

The authoritative payload is one consolidated human-readable parent comment. Issue metadata is a typed index to that payload, never a copy of it, and `runs[].result.output` is not the final deliverable. The leader writes and verifies `squad_verdict`, `squad_result_comment_id`, `squad_next_owner`, `squad_evidence_complete`, and the caller-provided `correlation_id` unchanged before recording `multica squad activity` and changing parent status.

Observe parent business state with `issue get`, the work graph with `issue children`, current and historical execution with `issue runs`, event freshness with `issue run-messages`, result readiness with `issue metadata list`, and evidence/steering with comments. A task is stalled only when no new run-message event arrives for the caller-configured freshness window; total elapsed time alone is not evidence of a stall. Preserve existing evidence and re-dispatch only the missing artifact or verification lane.

Cancellation is task-first across the complete descendant issue graph: recursively discover every child and descendant, enumerate and cancel every active task, re-discover the graph and confirm no active task remains, then set descendants deepest-first and the parent last to `cancelled`. Changing issue status alone does not interrupt running or queued work.

## Context and Memory Boundaries

- Company context contains only stable invariants shared by every agent.
- Squad instructions contain only that Squad's mission, activation rules, workflow, and artifact contracts.
- Profession files contain only stable professional behavior, not a fixed Squad roster.
- Project context contains domain facts and decisions with provenance.
- Issue context contains one bounded run and its DoD.
- Start unrelated runs fresh. Resume state only for the same objective when continuity is intentional.
- Pass referenced artifacts and concise evidence summaries across roles; do not copy entire conversations into prompts.

## Scope and Grounding

State assumptions explicitly. Ask one clarifying question when ambiguity changes the implementation path, target, or deliverable. Do not ask when safe repository reads or commands can resolve it.

Before multi-step work or any code change, define what done means and name the verification commands. Checkpoint after each significant step: what changed, what is verified, and what remains.

Use evidence. Cite a file path and line number for repository behavior or label the statement as a hypothesis. Never fabricate command output. State clearly when a command cannot be run.

Read before writing. Inspect the file's exports, immediate callers, tests, and shared utilities. If code structure is unclear, resolve it before editing.

Tests must protect business intent, not merely exercise an implementation. Never claim completion when anything required was skipped or unverified.

## Code Discipline

Prefer the minimum code that solves the current problem. Do not add abstractions, feature flags, dependencies, or generalized helpers until the current task needs them more than once.

Make surgical changes and match local conventions. Preserve unrelated user changes. When patterns conflict, choose the more recent, more tested, or more locally dominant pattern; state the deciding constraint and flag the other pattern separately.

Do not lock implementation details too early. Framework presets are allowed, but the core loop must remain portable across model providers and runtimes.

## Repository Invariants

- `AGENTS.md` and `CLAUDE.md` must remain byte-identical.
- Tracked files use logical role and instance names, never Multica UUIDs, mention links, tokens, runtime IDs, or private environment values.
- `workspace-context.md` contains company rules, never a hard-coded single-Squad roster.
- `agents/<profession>/` defines one primary profession; overlapping Squad membership is represented only in `squads/*/squad.json`.
- Every persistent Squad in Multica has a matching tracked definition and instructions file.
- Runtime automation records caller and runtime Multica CLI versions and depends only on fields verified on both sides.
- Apply topology only from clean `main` at `origin/main`, plan first, and prove convergence with a fresh read.
- Never archive agents or Squads, prune members, publish, deploy, or send externally unless the current task explicitly authorizes that action.
