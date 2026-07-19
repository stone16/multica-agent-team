# Agent Team

Git source of truth for a reusable agent company operating on Multica: seven domain-neutral Profession Profiles, nine intended Agent Instances, and five persistent functional Squads. The Orchestrator leads each baseline Squad and composes the smallest sufficient team for every Issue-scoped run.

This repo is being prepared for open-sourcing. Tracked files use neutral logical instance names only (Engineer-A, Engineer-B, Evaluator-A, Evaluator-B — no personal names), and all operational identity mappings live in shell-local sync variables or GitHub Actions secrets/variables, never in tracked files.

## Layout

| Path | Purpose | Maps to in Multica |
|---|---|---|
| `AGENTS.md` + `CLAUDE.md` | Byte-identical company operating system for any model editing the repository | Repository instructions |
| `workspace-context.md` | Company constitution, applies to every Multica agent | `workspace.context` field |
| `agents/<role>/personality.md` | Agent persona in 4 sections: Identity / Personal Goal / Touchstone / Constraints. Narrative for the first three; imperative bullets for Constraints | `agent.instructions` field |
| `agents/<role>/skill.md` | Agent operational rules — imperative, written in harness-template style. Self-contained per agent (no cross-references) | One Multica skill, mounted on the agent(s) for that profession |
| `templates/*.md` | Output templates. Team-specific content (roster, routing preamble) is canonical here; only the generic section skeleton mirrors `stone16/harness-template`. Not synced to Multica — agents inline them in their own `skill.md` | — |
| `scripts/sync-multica.sh` | Bridge from this repo to the Multica server (Multica has no git-sync). See "Syncing to Multica" | `multica skill update` / `multica agent update` |
| `.agents/skills/sync-multica/` | Repo-local operating procedure for planning, applying, and proving a Multica sync without committing operational identity | Codex repo skill |
| `deployments/agents.json` | Neutral logical instances, profession, runtime provider, and model intent; never personal names or UUIDs | Existing/creatable Multica agents |
| `squads/*/squad.json` + `instructions.md` | Persistent Squad topology and operating contracts | Multica Squads and membership |
| `scripts/sync-topology.py` | Non-destructive topology plan/apply/verify reconciler | Agents, runtimes/models, Squads, memberships |
| `.github/workflows/pr-sweep.yml` + `.github/scripts/pr-sweep.sh` + `tests/pr-sweep.test.sh` | Automated PR review chain. See "PR-Sweep Automation" | One Multica review issue per PR |

Each profession is two files. No shared skills, no cross-file references — every rule an agent needs is duplicated into that agent's `skill.md`. Duplication is the price of self-containment; we accept it.

## Roster

Seven professions, flat — vertical tiers are abolished. One directory per profession; overlapping Squad membership does not create a new profession.

| # | Profession | Path | Runtime / model (desired) | Focus |
|---|---|---|---|---|
| 1 | Orchestrator | `agents/orchestrator/` | Claude / Opus 4.8 | Objective ownership, role activation, DoD dispatch, verification, closure, PR-review adjudication |
| 2 | PM | `agents/pm/` | Claude / Opus 4.8 | PRD, issue split, product decisions and review |
| 3 | Designer | `agents/designer/` | Claude / Opus 4.8 | User journey, UX/UI, prototype and design review |
| 4 | Engineer | `agents/engineer/` | Two Codex instances, both `gpt-5.6-sol` | Implementation and non-author peer review |
| 5 | GTM | `agents/gtm/` | Grok runtime default | Positioning, launch, channel selection, growth experiments, market feedback |
| 6 | Evaluator | `agents/evaluator/` | Two Grok runtime-default instances | Independent DoD, behavior, security and performance verification |
| 7 | Researcher | `agents/researcher/` | Claude / Opus 4.8 | Primary-source-grounded evidence and uncertainty reduction |

The Engineer instances share one profile, as do the two Evaluators. Instances provide capacity or independent judgment; they do not create Senior/Junior tiers. Provider/model intent lives in `deployments/agents.json`; existing personal display-name mappings are supplied only for the sync process.

## Persistent Squads

| Squad | Mission | Default capability center |
|---|---|---|
| Discovery | Evidence-backed target user, problem, opportunity, and positioning | Researcher, GTM, PM |
| Experience | Coherent journey and testable product definition | PM, Designer |
| Delivery | Verified, reversible, shippable behavior | Engineer, PM/Designer as needed, Evaluator gate |
| Growth | Launch, acquisition, activation, retention, and commercial learning | GTM, PM |
| Reliability | Reliability, incidents, safety, maintenance, and product health | Engineer, Evaluator |

These are long-lived routing definitions, not permanent full-roster meetings or shared chat memory. An Issue has one owning Squad at a time, and each run activates only the roles with a distinct required output. Detailed entry/exit and artifact contracts live under `squads/`.

Assigning an Issue to a Squad tasks its Orchestrator. Everything after that is driven by Multica's native re-trigger: a member comment containing no mentions returns control to the current leader. No polling.

1. **Issue assigned to Squad** → Orchestrator reads the Issue, injected Squad instructions and roster, posts a plan, then ONE DoD-bearing delegation comment.
2. **Member delivers** → a mention-free evidence delivery re-triggers the current leader.
3. **Leader evaluates** → next step, independent Evaluator, capped rework, human gate, or close.
4. **All steps done** → completion summary plus durable artifact links and residual risks.

The stable state machine lives in `agents/orchestrator/skill.md`; each Squad's workflow contract lives in its own instructions. Discussions still run as `discussion`-label Issues, not chat sessions.

### Hub-and-spoke mentions

Only the current Squad leader may @-mention members, and only in delegation comments. Members never @-mention anyone — their mention-free delivery returns control to the leader. This topology structurally eliminates mention cycles.

### DoD protocol

Every delegation comment inlines a Definition of Done block:

```yaml
dod:
  outcome: <one sentence: what state counts as done>
  evidence: <what proof must be attached: test output / screenshots / links>
  verification: self | evaluator | dual_evaluator | human
  max_rounds: 2   # rework cap; when exceeded, the Squad leader escalates to the human
```

| Level | When |
|---|---|
| `self` | Low-risk work: docs, research memos. The Squad leader checks evidence and closes the step |
| `evaluator` | Deliverables entering mainline or user-visible surfaces. Evaluator independently re-runs the evidence before the step closes |
| `dual_evaluator` | High-risk or security-sensitive work. Two Evaluators receive independent contexts and reconcile after both verdicts exist |
| `human` | Irreversible actions: publishing, external sends, deploys. The Squad leader asks the human and does not proceed |

The delivery comment must address each `dod.evidence` item with actual evidence, item by item. A delivery narrative without evidence is a rework trigger, not a closure.

## Style Conventions

| File | Sections | Style | Inspired by |
|---|---|---|---|
| `personality.md` | Identity / Personal Goal / Touchstone / Constraints | First three are narrative (CrewAI-style second-person prose); Constraints is imperative bullets (positive + negative mixed) | CrewAI's `role_playing` template + `stone16/harness-template` AGENTS.md |
| `skill.md` | Hard Rules / Do Not / Triggers / Output formats / Examples | All imperative; tables for lookup surfaces | `stone16/harness-template` AGENTS.md |

The two files cover different scopes:

- **Personality `Constraints`** are **identity-level** — what kind of person/role you are ("Do not write code" because you are PM, not Engineer).
- **Skill `Do Not`** are **operational-level** — Multica platform and process rules ("Never @-mention anyone; your mention-free delivery comment returns control to the squad leader").

Some duplication is acceptable; it reinforces the rule across persona and procedure layers.

## Templates

The `templates/` folder is local reference only. When an agent needs to output a PRD, spec, or Change Proposal, it inlines the template structure into its own `skill.md` rather than referencing across files.

| Template | Used by |
|---|---|
| `product-requirement.md` | PM |
| `architecture-spec.md` | Engineer (spec-first for non-trivial implementation) |
| `change-proposal.md` | PM (wrap-up), Orchestrator (build-vs-buy decisions), GTM (launch and positioning decisions) |
| `eval-rubric.md` | Evaluator |
| `harness-task-spec.md` | Engineer (when work needs harness checkpoints) |
| `incident-report.md` | Anyone documenting a production incident |
| `user-feedback-report.md` | PM, GTM (market feedback synthesis) |
| `pr-description.md` | Any agent that opens a PR — the Engineer instances primarily; Evaluator when it ships tests or fixes |

GitHub also preloads `.github/PULL_REQUEST_TEMPLATE.md` in this repo. Keep it structurally aligned with `templates/pr-description.md`; the GitHub file is the ready-to-fill PR body, while `templates/pr-description.md` remains the instructional source with examples.

Agent-created PRs must be opened as Ready for review, never as GitHub Draft PRs. If the body is not filled, the agent keeps working locally instead of opening a placeholder PR.

Ownership rule: team-specific template content — the roster, the routing preamble (`Originating Multica issue:` / `Original author:` lines), and any squad-protocol wording — is canonical IN THIS REPO. Only the generic section skeleton mirrors `stone16/harness-template`, and upstream sync is for team-agnostic structure only: pull structural changes (new/renamed sections) from upstream, never push or overwrite the team-specific content here from it. After a template change, update each agent's `skill.md` that inlines it.

## PR-Sweep Automation

The team's automated code-review chain runs as a GitHub Action in this repo:

| File | Role |
|---|---|
| `.github/workflows/pr-sweep.yml` | Cron schedule (`*/15 * * * *`) + injects operational identity from secrets/variables + invokes the script |
| `.github/scripts/pr-sweep.sh` | Deterministic filter — enumerates open PRs across all non-archived `stone16/*` repos, decides which need review, creates or reuses one Multica issue per PR, and routes reconciled outcomes back to that same issue |
| `tests/pr-sweep.test.sh` | Unit tests for sentinel parsing, peer-lane pick, iteration counting, routing, debate convergence via `ceo-resolved`, read-failure skipping, and the Evaluator-authored lane guard |
| `.pr-sweep-ignore` | Transition-era fallback exclusion list; superseded by the `PR_SWEEP_IGNORE` Actions variable |

The STO-136 fixer-first follow-up design lives in `docs/pr-review-fixer-architecture.md`. Keep implementation, prompt, and test changes for that workflow in this `stone16/agent-team` repo; `multica-ai/multica` is only the runtime platform reached through Multica autopilot and the `multica` CLI.

### Why this shape

The cost driver in agent-driven workflows is **agent invocations**, not script runs. By doing the deterministic filter (sentinel match, SHA compare) in the GH-Actions-hosted shell script, we only invoke a review lane when there is genuinely new code to review. Empty sweeps cost ~$0.

The review prompt follows the Claude Code review shape we want to emulate: review the current PR head, focus on production-impacting bugs instead of style nits, require evidence in each finding, and leave a machine-readable marker after a real review. We keep that as Markdown prompt and Bash, not a new review service.

**Read-failure discipline**: every GitHub read in the script distinguishes an API failure from genuinely-empty data. Any failed read for a PR logs a `fetch failed … skipping this sweep` warning, increments the `prs_fetch_failed` counter in the sweep summary, and skips that PR entirely for the run — sentinel state is re-derived from the PR thread on the next sweep, so skipping is safe by design. No decision (peer-lane pick, dispatch, consensus, final sentinel) is ever made from error-empty data.

### Review lanes

Every PR — including documentation-only PRs — gets two independent reviews at the current head SHA; this is not a rotation:

- **Engineer peer lane** — general code quality, carried by the Engineer instance that did NOT author the PR. If Engineer-A authored, Engineer-B reviews, and vice versa; for non-Engineer authors (PM, human, or an unmapped author), the default is Engineer-A. The author is read from the machine-parsed `Original author: [@AgentName](mention://agent/<uuid>)` line in the PR body, so instances can share one bot login without ever reviewing their own PR. The body must carry exactly ONE `Original author:` line, and that line exactly ONE agent mention: duplicate author lines, zero mentions, or multiple mentions all make the author unparseable (logged), and the PR is treated as human-owned — this stops a crafted line with two mentions from resolving to conflicting identities and dodging the self-review guard.
- **Evaluator adversarial lane** — security, performance, dependency risk, adversarial inputs.

**Evaluator-authored PRs** are the exception: the adversarial lane never self-reviews. When the PR body's `Original author:` UUID matches `EVALUATOR_MENTION`, the sweep carries BOTH lanes with the two Engineer instances in a fixed pair-mode lane split — Engineer-A reviews with the peer code-quality lens; Engineer-B runs the adversarial checklist (security, performance, dependency risk, adversarial inputs — not a second peer pass), per the "Adversarial Lane Exception" in `agents/engineer/skill.md`. Both write the `engineer-reviewed` sentinel (never `evaluator-reviewed`), and consensus for that PR requires two `engineer-reviewed` sentinels from two DISTINCT trusted review comments as the two lanes — the LAST two valid such comments for the SHA (latest state wins), the earlier of the pair as peer and the latest as adversarial; verdict computation and embedded evidence always use the same two comments. The sweep parses per-comment: each counted comment must carry exactly one `engineer-reviewed` sentinel for the SHA, so a single comment stuffed with two sentinels satisfies neither lane (it is logged and ignored). The review-request text carries the lane attribution, and the outcome comment labels the lanes explicitly.

The lenses differ, but the evidence bar is identical: check out the PR head SHA into an isolated Multica worktree for full-repo context, `file:line` findings, production-impacting issues first, explicit verification status, strict verdict word, and no sentinel without a real review. The lanes do not coordinate in advance; the script reconciles the two verdicts.

### Required GitHub Actions secrets and variables

Set on this repository (`stone16/multica-agent-team`):

| Secret | What it is | Scope |
|---|---|---|
| `MULTICA_TOKEN` | Personal access token for the Multica identity the sweep acts as | Used by `multica login --token` so the script can create/update PR review issues and comments |
| `GH_PAT` | GitHub Personal Access Token | `repo` scope (read access to all `stone16/*` repos, including private). The default `GITHUB_TOKEN` only sees this one repo, so a PAT is required to enumerate cross-repo PRs |

Both are required; the workflow's first step fails loud if either is missing.

| Variable | What it is |
|---|---|
| `MULTICA_WORKSPACE_ID` | Multica workspace UUID. Required |
| `CEO_MENTION` | The ONLY mention the sweep ever emits, as `[@CEO](mention://agent/<uuid>)`. Required — every non-approve outcome routes here |
| `ENGINEER_A_MENTION`, `ENGINEER_B_MENTION`, `EVALUATOR_MENTION` | Roster mention links in the same form. They map a PR body's `Original author:` UUID to a roster identity — that mapping picks the peer lane (the sweep never mentions authors). Required — the workflow's check step FAILS before running the sweep when any of them (or `CEO_MENTION`) is unset |
| `ENGINEER_A_AGENT`, `ENGINEER_B_AGENT`, `EVALUATOR_AGENT`, `CEO_AGENT` | Compatibility-named Multica assignee variables; the script defaults to `Engineer-A` / `Engineer-B` / `Evaluator-A` / `Orchestrator` when unset |
| `TRUSTED_SENTINEL_AUTHORS` | GitHub logins (newline/space separated) whose PR comments may carry authoritative review sentinels. Defaults to the `GH_OWNER` login when unset — set it to the bot login(s) the agents comment through. Sentinels in comments from any other author are ignored with a log line, so arbitrary commenters on a public repo can never forge review state |
| `PR_SWEEP_IGNORE` | Newline-separated repo names to exclude from the sweep. Kept as an Actions variable so private repo names never live in tracked files |

Agent UUIDs and mention links are operational identity — never commit them.

### Sentinel protocol

After a review, each lane appends an HTML-comment sentinel to its PR review comment so the next sweep can tell what's already done:

```
<!-- engineer-reviewed: <head-sha> verdict: <approve|request-changes|block> -->
<!-- evaluator-reviewed: <head-sha> verdict: <approve|request-changes|block> -->
```

Both Engineer instances write `engineer-reviewed` — the sentinel is lane-scoped, not instance-scoped, so a re-review by the other instance stays comparable.

Two hard rules gate every sentinel parse:

- **Sentinel trust** — the sweep only honors sentinels found in comments whose GitHub author login is in `TRUSTED_SENTINEL_AUTHORS` (defaults to the `GH_OWNER` login). A sentinel-bearing comment from any other author is ignored with a log line; commenters cannot forge review state.
- **Strict verdict whitelist** — the verdict must be exactly `approve`, `request-changes`, or `block`. A sentinel carrying anything else (e.g. `approved`) is malformed and is not a sentinel at all.

When both lanes have written sentinels for the same SHA, the script writes one of:

```
<!-- consensus: <sha> verdict: <agreed-verdict> -->     # both agree — terminal for this SHA
<!-- debate: <sha> -->                                   # they disagree → escalate to the Orchestrator — NOT terminal
```

Only the consensus sentinel is terminal: the next sweep skips PRs that already have a consensus sentinel for the current SHA. New commits invalidate sentinels automatically (different SHA).

A debate converges through the compatibility-named Orchestrator resolution sentinel. After casting the deciding vote in the Multica review Issue, the Orchestrator posts on the PR, exactly:

```
<!-- ceo-resolved: <head-sha> verdict: <approve|request-changes|block> -->
```

The sweep then reconciles: debate + `ceo-resolved` for the SAME SHA → it writes the final consensus sentinel with the resolved verdict and finishes the PR (approve → the review Issue is closed FIRST; non-approve → the Orchestrator already owns rework). A debate without the compatibility sentinel is logged as waiting for Orchestrator adjudication and skipped.

Each PR gets exactly one Multica review issue. The PR URL is the logical idempotency key; the durable mapping is stored on that PR thread as:

```
<!-- multica-pr-review-issue: <issue-id> -->
```

The marker write is retried up to 3 times after issue creation; if it still fails, the sweep closes the just-created Multica issue again (compensating close) and logs the failure loudly — an unmarked live issue is never left behind silently for the next sweep to duplicate.

Reviewer dispatch is serialized through that single issue: the peer Engineer lane reviews first, then the Evaluator lane (or the reverse if the Evaluator sentinel already exists). New commits append a new review-request comment to the same issue; the head SHA makes older comments stale.

### Outcome routing

When both lanes have verdicts, the script reconciles and posts one Multica comment in the PR review Issue with the PR URL, head commit, final verdict, both lane verdicts, neutralized review bodies, and an `Action:` line. **Leader-only routing**: the script never @-mentions PR authors — every non-approve reconciled outcome mentions only the compatibility variable `CEO_MENTION`, and the Orchestrator dispatches rework:

| `Action:` value | Recipient | When |
|---|---|---|
| `ceo-followup` | `CEO_MENTION` | Both lanes agree on `request-changes` or `block`. The Orchestrator dispatches capped rework to the original author or escalates human-owned work |
| `ceo-debate` | `CEO_MENTION` | The lanes disagree. The Orchestrator casts the deciding vote and posts the `ceo-resolved` compatibility sentinel |

Follow-up is discussion-first, not blind stale-marking. The Orchestrator never implements fixes; `will-fix` means a routed dispatch. Rework reaches the author only through an Orchestrator delegation, then both lanes re-run on the new head SHA.

If both lanes approve, the script first marks the review Issue `done`, then writes the consensus sentinel. The Orchestrator is not involved in the approve path.

Reviewer behavior is in `agents/engineer/skill.md` (peer lane) and `agents/evaluator/skill.md` (adversarial lane). Do not edit the sentinel format in only one place — change both, update `tests/pr-sweep.test.sh`, and re-sync to Multica via `scripts/sync-multica.sh`.

### Scope and exclusions

The sweep enumerates **all non-archived** repos under `stone16/*` (up to 1000 repos and 1000 open PRs per repo). If either enumeration returns exactly its limit, the sweep treats it as saturated: it logs an `enumeration saturated` error and exits nonzero at the end of the run, so incomplete coverage always fails the workflow instead of silently skipping repos or PRs. To exclude a repo (personal experiment, third-party fork, separately-reviewed sub-team repo), add its name to the `PR_SWEEP_IGNORE` GitHub Actions variable, one repo name per line:

```
twitter-chrome-extension
auto-research
```

Empty variable = fall back to the tracked `.pr-sweep-ignore` file (same format; `#` comment lines allowed) during the transition; empty both = sweep everything. Prefer the variable — it keeps private repo names out of tracked files, which matters for the planned open-sourcing of this repo.

### Disabling the sweep

The cron is `*/15 * * * *`. To disable temporarily, comment out the `schedule` block in `.github/workflows/pr-sweep.yml`. Manual runs remain possible via `workflow_dispatch` from the GitHub Actions UI.

## Syncing to Multica

Multica has no native git-sync, so this repository uses two reconcilers:

- `scripts/sync-topology.py` manages tracked Agent Instance runtime/model intent plus Squad definitions and memberships. It never archives or removes.
- `scripts/sync-multica.sh` manages workspace context, profession skill content, agent instructions, and attachments.

```bash
scripts/sync-topology.py                    # read-only instance + Squad plan
scripts/sync-multica.sh                     # read-only content plan
scripts/sync-topology.py --apply            # create/update tracked non-destructive topology
scripts/sync-multica.sh --apply             # update context and Profession Profiles
scripts/sync-multica.sh --apply --agent engineer
scripts/sync-topology.py --verify           # fresh topology read; nonzero on drift
scripts/sync-multica.sh --verify           # fresh read; nonzero if any managed state still drifts
```

Dry-run is the default; only `--apply` writes. Both apply modes require a clean `main` at `origin/main`; verify always performs new Multica reads. `sync-topology.py` creates only tracked Squads and Agent Instances explicitly marked `create_if_missing`, and fails closed on extra members instead of pruning them. Auth is ambient, while UUIDs and runtime IDs remain deployed state and are never committed. Use the repo-local `$sync-multica` skill for the complete topology → content → fresh verify sequence.

## Do Not

- Do not introduce a shared `skills/` folder. Each agent owns its full skill content.
- Do not overwrite team-specific template content (roster, routing preamble) from upstream — it is canonical in this repo; only the generic section skeleton mirrors `stone16/harness-template`.
- Do not introduce a new profession without an entry in the Roster table and a corresponding `agents/<role>/` folder with both files, then a re-sync.
- Do not let anyone but the current Squad leader @-mention a member, and only in delegation comments. Members' delivery comments are mention-free — that is what returns control to the leader and keeps mention cycles structurally impossible.
- Do not dispatch work without an inline DoD block, and do not close a step whose delivery has not addressed every `dod.evidence` item.
- Do not commit a sentinel-writing change without updating `agents/engineer/skill.md` AND `agents/evaluator/skill.md` plus `tests/pr-sweep.test.sh`, then syncing to Multica — sentinel formats must stay in lock-step.
- Do not commit operational identity: agent UUIDs, mention links, workspace ids, tokens, or private repo names belong in GitHub Actions secrets/variables, not tracked files.
- Do not hand-edit agent instructions or skills on the Multica server without landing the change in this repo first. `scripts/sync-multica.sh` treats this repo as the source of truth and will overwrite server drift.
