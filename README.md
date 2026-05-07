# Agent Team

Per-agent personality + skill markdown for an 8-agent product team operating on Multica.

## Layout

| Path | Purpose | Maps to in Multica |
|---|---|---|
| `workspace-context.md` | Team constitution, applies to every agent | `workspace.context` field |
| `agents/<role>/personality.md` | Agent persona in 4 sections: Identity / Personal Goal / Touchstone / Constraints. Narrative for the first three; imperative bullets for Constraints | `agent.instructions` field |
| `agents/<role>/skill.md` | Agent operational rules — imperative, written in harness-template style. Self-contained per agent (no cross-references) | One Multica skill, mounted on this agent |
| `templates/*.md` | Local reference copies of `stone16/harness-template` artifact templates. Not synced to Multica — agents inline them in their own `skill.md` | — |

Each agent is two files. No shared skills, no cross-file references — every rule an agent needs is duplicated into that agent's `skill.md`. Duplication is the price of self-containment; we accept it.

## Roster

| # | Agent | Path | Model | Focus |
|---|---|---|---|---|
| 1 | CEO | `agents/ceo/` | Claude Opus | Strategy, ROI, direction |
| 2 | CTO | `agents/cto/` | DeepSeek-R1 / Opus | Tech strategy, build-vs-buy |
| 3 | Tech Lead | `agents/tech-lead/` | DeepSeek-R1 / Opus | Tech Spec, code architecture review |
| 4 | PM | `agents/pm/` | Claude Sonnet | PRD, issue split, discussion wrap-up, product review |
| 5 | Designer | `agents/designer/` | Claude Opus | UX/UI, design review |
| 6 | Senior Engineer | `agents/senior-engineer/` | Opus / Codex GPT-5.5 | Complex implementation, reviews Junior code |
| 7 | Junior Engineer | `agents/junior-engineer/` | Lower-end model | Routine implementation |
| 8 | QA | `agents/qa/` | Sonnet / Qwen | Behavioral, regression, edge cases |

## Discovery → Execution Flow

1. **User** opens a `discussion`-label issue.
2. **CEO + CTO + PM + Designer** comment with their perspective + Senior/Junior recommendation block.
3. **PM** wraps up: rewrites issue description as Change Proposal, creates child issues.
4. **Tech Lead** writes Tech Spec on `spec`-label child issues.
5. **Senior or Junior Engineer** implements `impl`-label child issues.
6. **Review chain**: code (Senior reviews Junior; Tech Lead reviews Senior) → product (PM + CEO + Designer) → behavior (QA).

## Style Conventions

| File | Sections | Style | Inspired by |
|---|---|---|---|
| `personality.md` | Identity / Personal Goal / Touchstone / Constraints | First three are narrative (CrewAI-style second-person prose); Constraints is imperative bullets (positive + negative mixed) | CrewAI's `role_playing` template + `stone16/harness-template` AGENTS.md |
| `skill.md` | Hard Rules / Do Not / Triggers / Output formats / Examples | All imperative; tables for lookup surfaces | `stone16/harness-template` AGENTS.md |

The two files cover different scopes:

- **Personality `Constraints`** are **identity-level** — what kind of person/role you are ("Do not write code" because you are PM, not engineer).
- **Skill `Do Not`** are **operational-level** — Multica platform and process rules ("Do not @-mention another agent" because that triggers an agent-to-agent loop).

Some duplication is acceptable; it reinforces the rule across persona and procedure layers.

## Templates

The `templates/` folder is local reference only. When an agent needs to output a PRD, Tech Spec, or Change Proposal, it inlines the template structure into its own `skill.md` rather than referencing across files.

| Template | Used by |
|---|---|
| `product-requirement.md` | PM |
| `architecture-spec.md` | Tech Lead |
| `change-proposal.md` | PM (for wrap-up), CTO (for build-vs-buy decisions) |
| `eval-rubric.md` | QA |
| `harness-task-spec.md` | Tech Lead (when work needs harness checkpoints) |
| `incident-report.md` | Anyone documenting a production incident |
| `user-feedback-report.md` | PM (when synthesizing user signal) |

If a template needs to change, change it in `stone16/harness-template` first, then mirror here, then update each agent's `skill.md` that inlines it.

## Do Not

- Do not introduce a shared `skills/` folder. Each agent owns its full skill content.
- Do not edit `templates/*.md` locally — mirror from upstream.
- Do not introduce a new agent without an entry in the Roster table and a corresponding `agents/<role>/` folder with both files.
- Do not allow agent-to-agent @-mentions. The human routes; agents execute.
