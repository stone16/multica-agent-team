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
| Orchestrator | Own the objective, compose the smallest sufficient team, dispatch with a DoD, verify, and close | Claude runtime; one `claude-opus-4-8` instance initially |
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

Squad membership is a capability roster, not an instruction to activate everybody. For every run, the Orchestrator selects the smallest sufficient set of roles and states the distinct output expected from each activated member.

An Issue has exactly one owning Squad at a time. Other Squads may be consulted through a child Issue or explicit mention. Transfer ownership only through an artifact-backed handoff with acceptance criteria; do not make `Discovery -> Experience -> Delivery -> Growth -> Reliability` an automatic waterfall.

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

1. Read the Issue, relevant ledger artifacts, current Squad roster, and Squad instructions.
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
7. Close only when the acceptance criteria are evidenced. Promote durable results to the Project ledger and record unresolved risks explicitly.

Only the current Squad leader may `@`-mention Squad members, and only for delegation. Members never route work by mention. A member's mention-free delivery returns control to the leader. Protocol identifiers such as `CEO_MENTION` or `ceo-resolved` may remain in automation for compatibility; they refer to the Orchestrator role.

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
- Apply topology only from clean `main` at `origin/main`, plan first, and prove convergence with a fresh read.
- Never archive agents or Squads, prune members, publish, deploy, or send externally unless the current task explicitly authorizes that action.
