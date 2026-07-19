# Research Note: Long-Lived Functional Squads for Multica

Date: 2026-07-19

## Executive judgment

The proposed model is sound with one important correction: make the **Squad definition** long-lived, not its accumulated conversation state or an always-active full roster.

Creating persistent `Discovery`, `Experience`, `Delivery`, `Growth`, and `Reliability` Squad objects in Multica is a reasonable way to give repeated workflows stable identity, leadership, membership defaults, instructions, permissions, and observability. The original four-Squad proposal covered discovery, experience, delivery, and reliability; this review adds Growth because no original Squad owned repeated launch, acquisition, activation, retention, and commercial-learning work. Each project or issue should still start a fresh, bounded **Squad run** with only the roles and context it needs.

This is not an industry standard that everyone implements identically. Leading frameworks support several coexisting patterns: one agent with tools, manager-and-specialists, peer handoffs, fixed workflow graphs, and dynamically created workers. The consistent design principles are composability, explicit state boundaries, minimal necessary context, and scaling the number of active agents to the task.

There is also an organizational-design caution. These functional Squads describe lifecycle capabilities. They should not become phase silos that throw work from Discovery to Experience to Delivery to Growth or Reliability without continuing ownership. A Team Topologies case study attributes knowledge loss, bottlenecks, and weak ownership to short-lived project teams handing work to a maintenance team, and reports moving toward long-lived teams aligned to streams of value instead. Treat the Multica Squads as reusable operating systems; preserve one project ledger and an accountable owner across transitions. ([Team Topologies at PureGym](https://teamtopologies.com/industry-examples/team-topologies-at-puregym-responding-better-to-business-needs-with-well-defined-software-teams))

## What the primary sources support

| Question | First-party evidence | Implication for Multica |
|---|---|---|
| When should work become multi-agent? | OpenAI recommends maximizing one agent first because additional agents add complexity and overhead; it suggests splitting when complex conditional logic or overlapping tools cause failures. ([OpenAI, “A practical guide to building agents”](https://openai.com/business/guides-and-resources/a-practical-guide-to-building-ai-agents)) AutoGen likewise says teams need more scaffolding and are intended for complex tasks requiring collaboration and diverse expertise. ([AutoGen, “Teams”](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/teams.html)) | A persistent Squad is a capability catalog, not a requirement to activate every member. Start each run with the smallest sufficient lane and add roles only for a dependency, independent judgment, parallelism, or a distinct tool boundary. |
| Can stable profiles be reused? | OpenAI defines an agent as configurable instructions, tools, model, handoffs, guardrails, and runtime behavior, and supports cloning a base agent with changed settings. ([OpenAI Agents SDK, “Agents”](https://openai.github.io/openai-agents-python/agents/)) CrewAI says well-designed agents can be reused across crews and contexts, advises specializing the role while keeping it versatile in application, and puts most design effort into the task rather than the persona. ([CrewAI, “Crafting Effective Agents”](https://docs.crewai.com/en/guides/agents/crafting-effective-agents)) | Keep profession profiles stable and domain-neutral. `Engineer-A` and `Engineer-B` can be two deployed instances of one Engineer profile; the same applies to two Evaluators unless their permanent rubrics, tools, or authority differ. |
| Should a team object retain state? | AutoGen teams are stateful, but its official guidance says to reset before an unrelated task and resume only related work. ([AutoGen, “Resetting a Team” and “Resuming a Team”](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/teams.html)) LangGraph separates thread-scoped checkpoints from cross-thread durable stores, and says per-invocation state is appropriate for most independent subagent requests. ([LangGraph, “Persistence”](https://docs.langchain.com/oss/python/langgraph/persistence), [“Subgraphs”](https://docs.langchain.com/oss/python/langgraph/use-subgraphs)) | Long-lived identity and configuration are safe; unbounded shared conversation history is not. Default to fresh issue/run state. Promote only reviewed facts and decisions into durable project artifacts. |
| How should specialists receive context? | Anthropic's production research system uses a lead orchestrator and workers with separate context windows, specific task boundaries, and condensed results. It also reports that multi-agent systems are a poor fit when all agents must share the same context or the work has many dependencies. ([Anthropic, “How we built our multi-agent research system”](https://www.anthropic.com/engineering/multi-agent-research-system)) LangGraph documents private state schemas for agents and explicit mapping between parent and subgraph state. ([LangGraph, “Subgraphs”](https://docs.langchain.com/oss/python/langgraph/use-subgraphs)) | Pass a bounded task contract and referenced artifacts, not the entire project conversation. A specialist returns a compact, evidence-linked artifact to the orchestrator. |
| Who should control the workflow? | OpenAI documents both a manager pattern, where the orchestrator retains control and calls specialists, and handoffs, where a specialist takes over. It also permits mixing LLM orchestration with deterministic code orchestration. ([OpenAI Agents SDK, “Agent orchestration”](https://openai.github.io/openai-agents-python/multi_agent/)) Anthropic uses an orchestrator-worker pattern for open-ended research. ([Anthropic](https://www.anthropic.com/engineering/multi-agent-research-system)) | Let the Orchestrator select roles, issue bounded work, and synthesize results. Use code or Multica workflow state for routing, retries, stage barriers, limits, and status transitions. Use model judgment for decomposition, synthesis, and ambiguous evaluation. |

## Recommended object model

The source of truth should distinguish four objects that are often conflated:

| Object | Lifetime | Canonical contents | Recommended home |
|---|---|---|---|
| `ProfessionProfile` | Long-lived and versioned | Responsibility, skills, tools, evidence contract, prohibited work | Git (`agents/<profession>/`) |
| `AgentInstance` | Long-lived deployment | `profile_ref`, runtime/model, identity, permissions, capacity | Multica, with desired non-secret configuration documented in Git |
| `SquadDefinition` | Long-lived and versioned | Objective, leader, required/default/optional roles, activation rules, workflow, entry/exit criteria, memory policy, evaluation policy | Git, synchronized to a persistent Multica Squad |
| `SquadRun` | One project, issue, incident, or bounded objective | Domain brief, selected instances, task graph, issue state, artifacts, DoD, budget, trace | Multica project/issue hierarchy |

The resulting behavior is:

```text
run behavior
= company contract
+ selected squad contract
+ project/domain brief
+ current task and Definition of Done
```

This preserves cross-domain reuse without pretending that a stable PM, Designer, or GTM profile already knows the pet, vaping, or next domain.

## Recommended baseline Squad definitions

These should be persistent Multica objects with reusable membership defaults, while activation remains per run.

| Squad | Stable mission | Default core | Optional activation examples | Exit artifact |
|---|---|---|---|---|
| Discovery | Establish evidence-backed opportunity, audience, and positioning | Orchestrator, Researcher, GTM | PM for product implications; parallel Researchers only for genuinely independent search lanes | Evidence memo, target segment, positioning hypothesis, unresolved risks |
| Experience | Turn a validated problem into a coherent journey and testable product definition | Orchestrator, PM, Designer | Researcher for user evidence gaps; GTM for promise/journey consistency | Journey, prototype/spec, assumptions, validation evidence, PRD-ready handoff |
| Delivery | Convert a mature PRD into verified, shippable behavior | Orchestrator, PM, one Engineer | Designer for experience decisions; second Engineer for parallel work or independent review; Evaluator(s) for risk-based gates | Shipped change plus verification evidence and deviations |
| Growth | Turn a validated proposition and available product into measurable adoption and commercial learning | Orchestrator, GTM, PM | Researcher for market evidence; Designer/Engineer for experiments; Evaluator for claim and result checks | Launch/experiment record, acquisition/activation/retention or revenue result, product feedback |
| Reliability | Maintain reliability, safety, and incremental product health | Orchestrator, Engineer, Evaluator | PM for prioritization; Designer for UX regressions; Researcher/GTM for recurring market signals | Incident/maintenance record, verified fix, follow-up decision |

`Required`, `default`, and `optional` are different concepts. A member may belong to a long-lived Squad without receiving every issue. Two Evaluators should both run only when independence or separate evaluation lenses justify the extra cost; otherwise one lane is enough.

## Should there be more than four Squads?

Yes, but the initial topology should add only one more: **Growth**. The four proposed Squads cover opportunity discovery, experience definition, product delivery, and technical operation. They do not clearly own the repeated post-positioning work of launch strategy, distribution, acquisition, activation, retention, and commercial learning. Putting that work into Research would confuse evidence gathering with market execution; putting it into Operations would confuse product reliability with growth outcomes.

This is a recommendation derived from the current profession set, especially the decision to retain GTM as a distinct reusable capability; it is not an external standard. Growth should collaborate with Discovery and Delivery rather than become a fifth sequential handoff stage.

| Classification | Candidate | Decision rule | Why |
|---|---|---|---|
| **Create now** | **Growth** | The company expects to launch or grow products, not only discover and build them | Stable mission: turn a validated value proposition and available product capability into measurable demand, activation, retention, or revenue. Core: Orchestrator + GTM; default: PM; optional: Researcher, Designer, Engineer, Evaluator. Exit artifact: channel/message experiments, measurement, commercial result, and product feedback. |
| **Conditional future Squad** | **Product / value-stream Squad** | Create one when a durable product needs continuous end-to-end ownership, or when lifecycle handoff rework becomes material | Team Topologies defines a stream-aligned team as owning outcomes across an entire slice of the business domain and describes it as “you build it, you run it,” without functional handoffs. The product Squad would become the primary owner and consume the functional Squads through collaboration or service interactions. ([Team Topologies, “Key concepts”](https://teamtopologies.com/key-concepts)) |
| **Conditional future Squad** | **Strategy & Portfolio** | Create only when multiple active ventures compete for budget/capacity and prioritization becomes a repeated multi-role workflow | Before that threshold, portfolio decisions belong in company governance led by the Orchestrator, supported by PM/GTM/Research artifacts. A new Squad without a recurring queue and distinct output contract would add routing overhead without capability. |
| **Conditional future Squad** | **Platform & Enablement** | Create after at least two product/value streams repeatedly consume the same internal runtime, deployment, data, evaluation, or developer service | Team Topologies describes platform teams as providing an internal product that accelerates stream-aligned teams, while enabling teams temporarily help other teams overcome obstacles and then move on. A platform should follow demonstrated internal demand, not be created speculatively. ([Team Topologies](https://teamtopologies.com/key-concepts)) |
| **Conditional future Squad** | **Security, Trust & Compliance** | Create when regulated products, sensitive data, high-impact decisions, adversarial abuse, or a required independent control function generate a persistent queue | Until then, security/privacy/risk requirements should be cross-cutting policy, threat-model and evaluator gates inside every Squad. NIST defines `GOVERN` as cross-cutting and says compliance and evaluation aspects should be integrated into the other AI risk functions. ([NIST AI RMF 1.0](https://doi.org/10.6028/NIST.AI.100-1), [NIST AI RMF Playbook](https://www.nist.gov/itl/ai-risk-management-framework/nist-ai-rmf-playbook)) |
| **Conditional future Squad** | **Complicated Subsystem** | Create only when a recurring subsystem requires scarce, deep expertise that ordinary Engineers cannot reasonably absorb | Team Topologies reserves this topology for work requiring substantial specialist technical or mathematical expertise. It is not a synonym for “hard engineering.” ([Team Topologies](https://teamtopologies.com/key-concepts)) |
| **Shared service / gate now** | **Evaluation & Assurance** | Keep as an independent service lane until it has a persistent direct-assignment queue, distinct authority, and a multi-step reconciliation workflow | Evaluation is needed across Discovery, Experience, Delivery, Growth, and Reliability. That makes the policy cross-cutting; it does not automatically make it a separate Squad. If dual independent Evaluators are routinely assigned and reconciled as one unit, promote this service to a persistent Assurance Squad later. |
| **Not a separate Squad** | **Incident Response** | Keep inside Reliability unless incident volume requires dedicated on-call capacity | Incidents are a trigger and workflow mode for Reliability, not a new durable capability boundary by default. |
| **Not a separate Squad** | **Data, Analytics, Legal, Finance, Content** | Begin as a skill, tool, evaluator lens, or optional specialist; promote only when the same bounded responsibility recurs and needs its own queue and artifact contract | A profession or skill is not automatically a Squad. OpenAI recommends maximizing the existing agent before splitting because extra agents and orchestration add complexity and overhead. ([OpenAI, “A practical guide to building agents”](https://openai.com/business/guides-and-resources/a-practical-guide-to-building-ai-agents)) |

This yields an initial topology of **five persistent functional Squads**:

1. Discovery
2. Experience
3. Delivery
4. Growth
5. Reliability

The first four original names can remain if naming stability matters, but `Discovery`, `Experience`, `Delivery`, `Growth`, and `Reliability` communicate durable outcomes more clearly than department names or lifecycle phases.

Do not pre-create placeholder Squads for every plausible future function. A candidate graduates to a Squad only when all four conditions hold:

1. it has a repeated incoming work queue;
2. it has a distinct outcome and artifact contract;
3. it needs stable leadership, membership defaults, or permissions;
4. routing it independently measurably reduces cognitive load or handoff failure.

Otherwise it remains a role, skill, gate, or temporary collaboration. Team Topologies' three interaction modes support this distinction: time-bounded collaboration for discovery, X-as-a-Service for a stable consumable capability, and facilitation for temporary help. ([Team Topologies](https://teamtopologies.com/key-concepts))

## Context and memory policy

Use five explicit scopes:

1. **Company context:** small, stable collaboration and safety rules shared by all agents.
2. **Squad context:** the Squad's workflow, role activation rules, artifact contracts, and exit criteria.
3. **Project/domain context:** evidence-backed facts and decisions for one venture or product, referenced rather than copied wholesale.
4. **Run context:** one issue/task's plan, messages, tool results, and DoD; fresh by default.
5. **Durable artifact ledger:** approved research, PRDs, decisions, code, eval results, and incident records. This, not chat history, is product state.

Cross-domain runs should never resume old team conversation state merely because they use the same Squad. Resume state only for the same objective when continuity is intentional. Summarize completed phases into artifacts before a handoff; give the receiving role the artifact, decision log, and open questions rather than every prior message.

## Risks and controls

| Risk | Failure mode | Structural control |
|---|---|---|
| Over-specialization | Many narrow agents duplicate work, require routing, and make evaluation expensive | Add a new profile only when a repeated responsibility has a materially different tool set, evidence contract, or authority. Otherwise add a task instruction, skill, or instance. |
| Full-roster activation | Every issue triggers all members because they are listed in the Squad | Define activation rules and an effort budget; the Orchestrator must explain each activated role's distinct output. |
| Context contamination | Old domain assumptions or another role's reasoning leak into a new run | Fresh issue state by default; private specialist context; artifact-based handoffs; explicit project identifiers and provenance. |
| Phase silos | Functional Squads optimize their local output and hand off responsibility | Keep one accountable Orchestrator/project owner, one project ledger, explicit acceptance criteria, and a feedback path to earlier Squads. For durable products, consider a domain/value-stream Squad that owns outcomes across phases. |
| Central bottleneck | The Orchestrator becomes a verbose relay or must decide deterministic state | Put routing, retry, counting, stage barriers, and status logic in code; let the Orchestrator handle judgment and exceptions. |
| False independence | Two Evaluators share the same conversation, assumptions, or draft verdict | Give independent input contexts, forbid pre-verdict coordination, reconcile only after both outputs exist, and rotate models only when evals show useful diversity. |

Anthropic reports early multi-agent failures including spawning excessive workers for simple queries, duplicated searches, and coordination errors; it recommends scaling effort to task complexity and giving workers explicit objectives, output formats, tools, sources, and boundaries. It also reports materially higher token use for multi-agent systems, reinforcing the need for activation budgets. ([Anthropic](https://www.anthropic.com/engineering/multi-agent-research-system))

## Local Multica evidence

Read-only inspection of the installed official CLI showed:

- `multica 0.4.4` exposes persistent `squad create|get|list|update|delete` commands.
- A Squad has a name, description, leader, and instructions.
- `squad member add|remove|set-role` manages durable membership and per-Squad roles.
- `issue create` and `issue update` accept an agent, member, or Squad as assignee; issues also support parents and ordered stages.

These surfaces are a good fit for `SquadDefinition` as the persistent object and an issue/project hierarchy as `SquadRun`. The CLI does not expose a separate `squad run` object, so this mapping is an architectural inference, not a documented Multica product guarantee.

Commands inspected:

```bash
multica --version
multica squad --help
multica squad create --help
multica squad update --help
multica squad member --help
multica squad member set-role --help
multica issue create --help
multica issue update --help
```

No remote state was mutated. `multica squad list --output json` could not be verified because the server address failed to resolve from the current sandbox, so this note makes no claim about the workspace's current remote Squads.

## Decision

Create the five baseline long-lived Multica Squad objects—`Discovery`, `Experience`, `Delivery`, `Growth`, and `Reliability`—but codify them as versioned **definitions** with issue-scoped runs. Do not clone separate copies of every agent per Squad, do not activate the full roster by default, and do not share conversation memory across unrelated domains.

After a few real projects, evaluate each Squad on outcome quality, handoff rework, role activation frequency, latency, token/runtime cost, and human interventions. Merge or split profiles and Squads only from that evidence. If repeated lifecycle handoffs become the dominant failure, add a long-lived domain/value-stream Squad for that product while retaining the five functional Squads as specialist capability pools.
