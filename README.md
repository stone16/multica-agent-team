# Agent Team

Per-agent personality + skill markdown for a 10-agent product team operating on Multica.

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
| 6 | Senior Engineer | `agents/senior-engineer/` | Opus / Codex GPT-5.5 | Complex implementation, reviews **every** production-code PR (any author) |
| 7 | Junior Engineer | `agents/junior-engineer/` | Lower-end model | Routine implementation |
| 8 | Security & Performance Reviewer | `agents/security-perf-reviewer/` | (model TBD) | Independent second reviewer on every production-code PR; security + performance focus |
| 9 | QA | `agents/qa/` | Sonnet / Qwen | Behavioral, regression, edge cases |
| 10 | Researcher | `agents/researcher/` | Claude Opus (high effort) | Primary-source-grounded research memos: companies, markets, mining projects, quant strategies, regulatory regimes |

## Discovery → Execution Flow

1. **User** opens a `discussion`-label issue.
2. **CEO + CTO + PM + Designer** comment with their perspective + Senior/Junior recommendation block.
3. **PM** wraps up: rewrites issue description as Change Proposal, creates child issues.
4. **Tech Lead** writes Tech Spec on `spec`-label child issues.
5. **Senior or Junior Engineer** implements `impl`-label child issues.
6. **Review chain**:
   - **code** — Senior Engineer + Security & Performance Reviewer review every production-code PR independently; the `pr-sweep.sh` script reconciles their verdicts (consensus or escalate-to-human). Tech Lead reviews architecture for spec compliance. See "PR-Sweep Automation" below.
   - **product** — PM + CEO + Designer review for user-visible outcome match.
   - **behavior** — QA exercises preview deploys against the three-angle pattern (happy / expected-failure / weird).

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
| `pr-description.md` | CTO, Tech Lead, Senior Engineer, Junior Engineer (every PR) |

GitHub also preloads `.github/PULL_REQUEST_TEMPLATE.md` in this repo. Keep it structurally aligned with `templates/pr-description.md`; the GitHub file is the ready-to-fill PR body, while `templates/pr-description.md` remains the instructional source with examples.

Agent-created PRs must be opened as Ready for review, never as GitHub Draft PRs. If the body is not filled, the agent keeps working locally instead of opening a placeholder PR.

If a template needs to change, change it in `stone16/harness-template` first, then mirror here, then update each agent's `skill.md` that inlines it.

## PR-Sweep Automation

The team's automated code-review chain runs as a GitHub Action in this repo:

| File | Role |
|---|---|
| `.github/workflows/pr-sweep.yml` | Cron schedule (`*/15 * * * *`) + invokes the script |
| `.github/scripts/pr-sweep.sh` | Deterministic filter — enumerates open PRs across all non-archived `stone16/*` repos, decides which need review, creates or reuses one Multica issue per PR, and posts actionable review outcomes back to that same issue |
| `.pr-sweep-ignore` | Optional newline-separated list of repo names to exclude from the sweep |

### Why this shape

The cost driver in agent-driven workflows is **agent invocations**, not script runs. By doing the deterministic filter (sentinel match, SHA compare) in the GH-Actions-hosted shell script, we only invoke Hao or Dustin when there is genuinely new code to review. Empty sweeps cost ~$0.

The review prompt follows the Claude Code review shape we want to emulate: review the current PR head, focus on production-impacting bugs instead of style nits, require evidence in each finding, and leave a machine-readable marker after a real review. We keep that as Markdown prompt and Bash, not a new review service.

Hao and Dustin are not a rotation. For every PR — including documentation-only PRs — the sweep gets both reviewers onto the current SHA, but it serializes that work through one PR-owned Multica issue instead of opening reviewer batch issues. Hao carries the general Senior Engineer code-quality lane; Dustin carries the security, performance, dependency-risk, and adversarial-input lane. Their required evidence bar is identical: full repo context (each reviewer checks out the PR head SHA into an isolated Multica worktree before reading code), `file:line` findings, production-impacting issues first, explicit verification status, strict verdict word, and no sentinel without a real review.

### Required GitHub Actions secrets

To enable the workflow, set these secrets on this repository (`stone16/agent-team`):

| Secret | What it is | Scope |
|---|---|---|
| `MULTICA_TOKEN` | Personal access token for the Hao/Eng Multica agent identity | Used by `multica login --token` so the script can create/update PR review issues and comments |
| `GH_PAT` | GitHub Personal Access Token | `repo` scope (read access to all `stone16/*` repos, including private). The default `GITHUB_TOKEN` only sees this one repo, so a PAT is required to enumerate cross-repo PRs |

Both are required. The workflow's first step fails loud if either is missing.

### Sentinel protocol

After a review, each reviewer appends an HTML-comment sentinel to their review comment so the next sweep can tell what's already done:

```
<!-- hao-reviewed: <head-sha> verdict: <approve|request-changes|block> -->
<!-- dustin-reviewed: <head-sha> verdict: <approve|request-changes|block> -->
```

When both reviewers have written sentinels for the same SHA, the script writes one of:

```
<!-- consensus: <sha> verdict: <agreed-verdict> -->     # both agree
<!-- debate: <sha> -->                                   # they disagree → escalate to human
```

The next sweep skips PRs that already have a final sentinel for the current SHA. New commits invalidate the sentinel automatically (different SHA).

Each PR gets exactly one Multica review issue. The mapping is stored on the PR thread as:

```
<!-- multica-pr-review-issue: <issue-id> -->
```

The script does not require a PR body to name an originating Multica issue or original author. That condition was wrong: not every PR starts from Multica. PR review state now lives in the PR-owned review issue.

Reviewer dispatch is serialized through the single issue to avoid multiple Multica issues for one PR:

- If neither reviewer has reviewed the current SHA, the issue is assigned to Hao first.
- After Hao's sentinel appears, the same issue is assigned to Dustin.
- If Dustin reviewed first for any reason, the same issue is assigned to Hao.
- New commits append a new review-request comment to the same issue; the head SHA makes older comments stale.

If the reconciled outcome has action items (`request-changes`, `block`, or reviewer disagreement), the script posts one Multica comment in the PR review issue with the PR URL, head commit, final verdict, both reviewer verdicts, the matching review bodies with review sentinels stripped, and an `Action:` line indicating one of:

| `Action:` value | Recipient mention | When |
|---|---|---|
| `cto-followup` | `CTO_MENTION` | Hao and Dustin agree on `request-changes` or `block`. CTO owns the next step in the same issue. |
| `cto-debate` | `CTO_MENTION` | Reviewers disagree. CTO casts the deciding vote in the same issue. |

If both reviewers approve, the script writes the PR consensus sentinel and marks the review issue `done` without mentioning CTO. If the PR is closed or merged before approval, close the review issue manually; the sweep only enumerates open PRs.

Reviewer behavior is in `agents/senior-engineer/skill.md` (Hao) and `agents/security-perf-reviewer/skill.md` (Dustin). Do not edit the sentinel format in only one place — change both, and re-sync to Multica via `multica skill update`.

### Scope and exclusions

The sweep enumerates **all non-archived** repos under `stone16/*`. To exclude a repo (personal experiment, third-party fork, separately-reviewed sub-team repo), add its name to `.pr-sweep-ignore`:

```
# .pr-sweep-ignore
twitter-chrome-extension
auto-research
```

Empty file = sweep everything. Comment lines (`#`) are ignored.

### Disabling the sweep

The cron is `*/15 * * * *`. To disable temporarily, comment out the `schedule` block in `.github/workflows/pr-sweep.yml`. Manual runs remain possible via `workflow_dispatch` from the GitHub Actions UI.

## Do Not

- Do not introduce a shared `skills/` folder. Each agent owns its full skill content.
- Do not edit `templates/*.md` locally — mirror from upstream.
- Do not introduce a new agent without an entry in the Roster table and a corresponding `agents/<role>/` folder with both files.
- Do not allow agent-to-agent @-mentions. The human routes; agents execute.
- Do not commit a sentinel-writing change without updating BOTH `agents/senior-engineer/skill.md` and `agents/security-perf-reviewer/skill.md` plus syncing to Multica — sentinel formats must stay in lock-step.
