# Agent Team

Per-profession personality + skill markdown for a 7-profession product squad operating on Multica. The CEO agent is the single squad leader; every other profession executes dispatched steps against an inline Definition of Done.

This repo is being prepared for open-sourcing. Tracked files use neutral roster names only (Engineer-A, Engineer-B, Evaluator — no personal names), and all operational identity (agent UUIDs, mention links, workspace id, private repo names) lives in GitHub Actions secrets/variables, never in tracked files.

## Layout

| Path | Purpose | Maps to in Multica |
|---|---|---|
| `workspace-context.md` | Team constitution, applies to every agent | `workspace.context` field |
| `agents/<role>/personality.md` | Agent persona in 4 sections: Identity / Personal Goal / Touchstone / Constraints. Narrative for the first three; imperative bullets for Constraints | `agent.instructions` field |
| `agents/<role>/skill.md` | Agent operational rules — imperative, written in harness-template style. Self-contained per agent (no cross-references) | One Multica skill, mounted on the agent(s) for that profession |
| `templates/*.md` | Output templates. Team-specific content (roster, routing preamble) is canonical here; only the generic section skeleton mirrors `stone16/harness-template`. Not synced to Multica — agents inline them in their own `skill.md` | — |
| `scripts/sync-multica.sh` | Bridge from this repo to the Multica server (Multica has no git-sync). See "Syncing to Multica" | `multica skill update` / `multica agent update` |
| `.github/workflows/pr-sweep.yml` + `.github/scripts/pr-sweep.sh` + `tests/pr-sweep.test.sh` | Automated PR review chain. See "PR-Sweep Automation" | One Multica review issue per PR |

Each profession is two files. No shared skills, no cross-file references — every rule an agent needs is duplicated into that agent's `skill.md`. Duplication is the price of self-containment; we accept it.

## Roster

Seven professions, flat — vertical tiers (Senior/Junior, CTO/Tech Lead) are abolished. One directory per profession.

| # | Profession | Path | Runtime / model (desired) | Focus |
|---|---|---|---|---|
| 1 | CEO (squad leader) | `agents/ceo/` | Claude Code / strongest available model | Orchestration: plan, dispatch with DoD, verify, close. Also strategy, ROI, build-vs-buy, and PR-review adjudication |
| 2 | PM | `agents/pm/` | Claude Code / Sonnet | PRD, issue split, product review |
| 3 | Designer | `agents/designer/` | Claude Code / Opus | UX/UI, design review |
| 4 | Engineer | `agents/engineer/` | Two instances: **Engineer-A** (Claude Code), **Engineer-B** (Codex) | All implementation. Peer code-review lane for PRs authored by the other instance |
| 5 | GTM | `agents/gtm/` | Claude Code / Sonnet or Opus | Positioning, launch plans, channel selection, growth experiments, market feedback synthesis |
| 6 | Evaluator | `agents/evaluator/` | Claude Code / Opus | DoD verification, behavioral testing (happy / expected-failure / weird), adversarial review lane (security, performance, dependency risk, adversarial inputs), weekly eval rollup |
| 7 | Researcher | `agents/researcher/` | Claude Code / Opus, high effort | Primary-source-grounded research memos: companies, markets, mining projects, quant strategies, regulatory regimes |

The two Engineer instances share the `agents/engineer/` files; which instance an agent is (A or B) is server-side configuration, visible in the agent name. Either instance can take fresh implementation work; rework on an existing PR goes back to its original author (always as a CEO dispatch — the sweep script never mentions authors); peer review always goes to the non-author instance.

## Squad Flow

Multica has no declarative pipeline — the CEO's instructions ARE the workflow. Assigning an issue to the squad tasks the leader; everything after that is driven by Multica's native re-trigger (a member comment containing no mentions re-triggers the leader). No polling.

1. **Issue assigned to squad** → CEO reads the issue and roster, posts a plan comment (numbered steps, each with target profession + DoD), then posts ONE delegation comment @-mentioning the member(s) for the first step(s).
2. **Member delivers** → a mention-free delivery comment addressing each `dod.evidence` item re-triggers the CEO, which checks evidence item by item: dispatch the next step, dispatch the Evaluator (`verification: evaluator`), dispatch rework with the gap named, or — past `max_rounds` — stop and escalate to the human.
3. **Anything else re-triggers the CEO** (human comment, cross-reference) → route it, or exit silently.
4. **All steps done** → CEO posts a completion summary: what shipped, evidence links, deviations, one evaluation note per member dispatched.

The full state machine lives in `agents/ceo/skill.md`. Discussions still run as `discussion`-label issues, not chat sessions.

### Hub-and-spoke mentions

Only the CEO may @-mention squad members, and only in delegation comments. Members never @-mention anyone — their mention-free delivery comment is what returns control to the leader. This topology structurally eliminates mention cycles; do not weaken it.

### DoD protocol

Every delegation comment inlines a Definition of Done block:

```yaml
dod:
  outcome: <one sentence: what state counts as done>
  evidence: <what proof must be attached: test output / screenshots / links>
  verification: self | evaluator | human
  max_rounds: 2   # rework cap; when exceeded, CEO escalates to the human
```

| Level | When |
|---|---|
| `self` | Low-risk work: docs, research memos. CEO checks evidence and closes the step |
| `evaluator` | Deliverables entering mainline or user-visible surfaces. Evaluator independently re-runs the evidence before the step closes |
| `human` | Irreversible actions: publishing, external sends, deploys. CEO asks the human and does not proceed |

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
| `change-proposal.md` | PM (wrap-up), CEO (build-vs-buy decisions), GTM (launch and positioning decisions) |
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

### Why this shape

The cost driver in agent-driven workflows is **agent invocations**, not script runs. By doing the deterministic filter (sentinel match, SHA compare) in the GH-Actions-hosted shell script, we only invoke a review lane when there is genuinely new code to review. Empty sweeps cost ~$0.

The review prompt follows the Claude Code review shape we want to emulate: review the current PR head, focus on production-impacting bugs instead of style nits, require evidence in each finding, and leave a machine-readable marker after a real review. We keep that as Markdown prompt and Bash, not a new review service.

**Read-failure discipline**: every GitHub read in the script distinguishes an API failure from genuinely-empty data. Any failed read for a PR logs a `fetch failed … skipping this sweep` warning, increments the `prs_fetch_failed` counter in the sweep summary, and skips that PR entirely for the run — sentinel state is re-derived from the PR thread on the next sweep, so skipping is safe by design. No decision (peer-lane pick, dispatch, consensus, final sentinel) is ever made from error-empty data.

### Review lanes

Every PR — including documentation-only PRs — gets two independent reviews at the current head SHA; this is not a rotation:

- **Engineer peer lane** — general code quality, carried by the Engineer instance that did NOT author the PR. If Engineer-A authored, Engineer-B reviews, and vice versa; for non-Engineer authors (PM, human, or an unmapped author), the default is Engineer-A. The author is read from the machine-parsed `Original author: [@AgentName](mention://agent/<uuid>)` line in the PR body, so instances can share one bot login without ever reviewing their own PR. The line must carry exactly ONE agent mention: zero or multiple mentions make the author unparseable (logged), and the PR is treated as human-owned — this stops a crafted line with two mentions from resolving to conflicting identities and dodging the self-review guard.
- **Evaluator adversarial lane** — security, performance, dependency risk, adversarial inputs.

**Evaluator-authored PRs** are the exception: the adversarial lane never self-reviews. When the PR body's `Original author:` UUID matches `EVALUATOR_MENTION`, the sweep carries BOTH lanes with the two Engineer instances in a fixed pair-mode lane split — Engineer-A reviews with the peer code-quality lens; Engineer-B runs the adversarial checklist (security, performance, dependency risk, adversarial inputs — not a second peer pass), per the "Adversarial Lane Exception" in `agents/engineer/skill.md`. Both write the `engineer-reviewed` sentinel (never `evaluator-reviewed`), and consensus for that PR requires two `engineer-reviewed` sentinels from two DISTINCT trusted review comments as the two lanes (first = peer, second = adversarial). The sweep parses per-comment: each counted comment must carry exactly one `engineer-reviewed` sentinel for the SHA, so a single comment stuffed with two sentinels satisfies neither lane (it is logged and ignored). The review-request text carries the lane attribution, and the outcome comment labels the lanes explicitly.

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
| `ENGINEER_A_AGENT`, `ENGINEER_B_AGENT`, `EVALUATOR_AGENT`, `CEO_AGENT` | Multica assignee names; the script defaults to `Engineer-A` / `Engineer-B` / `Evaluator` / `CEO` when unset |
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
<!-- debate: <sha> -->                                   # they disagree → escalate to the CEO — NOT terminal
```

Only the consensus sentinel is terminal: the next sweep skips PRs that already have a consensus sentinel for the current SHA. New commits invalidate sentinels automatically (different SHA).

A debate converges through the CEO resolution sentinel. After casting the deciding vote in the Multica review issue, the CEO posts on the PR, exactly:

```
<!-- ceo-resolved: <head-sha> verdict: <approve|request-changes|block> -->
```

The sweep then reconciles: debate + `ceo-resolved` for the SAME SHA → it writes the final consensus sentinel with the resolved verdict and finishes the PR (approve → the review issue is closed FIRST, and the terminal consensus sentinel is only written after a successful close; non-approve → the CEO already owns rework from the adjudication, so the sweep records the verdict and posts no new outcome comment). A debate without a `ceo-resolved` sentinel is logged as waiting for CEO adjudication and skipped — never treated as converged.

Each PR gets exactly one Multica review issue. The PR URL is the logical idempotency key; the durable mapping is stored on that PR thread as:

```
<!-- multica-pr-review-issue: <issue-id> -->
```

The marker write is retried up to 3 times after issue creation; if it still fails, the sweep closes the just-created Multica issue again (compensating close) and logs the failure loudly — an unmarked live issue is never left behind silently for the next sweep to duplicate.

Reviewer dispatch is serialized through that single issue: the peer Engineer lane reviews first, then the Evaluator lane (or the reverse if the Evaluator sentinel already exists). New commits append a new review-request comment to the same issue; the head SHA makes older comments stale.

### Outcome routing

When both lanes have verdicts, the script reconciles and posts one Multica comment in the PR review issue with the PR URL, head commit, final verdict, both lane verdicts, the matching review bodies (sentinels stripped, and mention-neutralized: any `mention://` URI inside a reviewer body — including HTML-entity-encoded variants such as `mention&#58;//`, `mention&#x3a;//`, and `mention&#x3A;//`, which Markdown would otherwise decode back into the live scheme — is rewritten to `mention[:]//` so it renders readably but can never fire a live mention), and an `Action:` line. **Leader-only routing**: the script never @-mentions PR authors — every non-approve reconciled outcome mentions only `CEO_MENTION`, and the CEO dispatches rework:

| `Action:` value | Recipient | When |
|---|---|---|
| `ceo-followup` | `CEO_MENTION` | Both lanes agree on `request-changes` or `block`. The CEO dispatches rework to the PR's author agent (delegation comment with a DoD referencing the review findings). The outcome comment carries a `- Original author:` line — either the exact mention markdown parsed from the PR body, wrapped in backticks so it stays informational and never acts as a live mention, or `unknown (human-authored or preamble unparseable) — no agent rework target; treat as human-owned`. It also carries an ADVISORY rework-iteration count ("rework iteration N of `MAX_REVIEW_ITERATIONS`", default cap 3 distinct non-approve head SHAs) — the script no longer enforces the cap; the CEO does, escalating to the human instead of dispatching once the advisory line reports the cap reached (a fourth iteration is never authorized) |
| `ceo-debate` | `CEO_MENTION` | The lanes disagree. CEO casts the deciding vote in the same issue, then posts the `ceo-resolved` resolution sentinel on the PR — that sentinel is what lets the next sweep converge the debate |

Follow-up is discussion-first, not blind stale-marking: each finding gets a `will-fix` / `already-fixed` / `wont-fix` / `needs-discussion` reply, the thread stays unresolved until the parties agree, and a summary comment lands before resolution. The CEO never implements fixes itself — a `will-fix` from the CEO means a routed dispatch. Rework reaches the author only as a CEO delegation comment; the author then pushes fixes to the PR branch and the next sweep re-runs both lanes at the new head SHA.

If both lanes approve, the script first marks the review issue `done`, then writes the consensus sentinel — the terminal sentinel is only written after a successful close, so a failed close logs a warning and is retried on the next sweep instead of being sealed behind a terminal sentinel. The CEO is not involved. If the PR is closed or merged before approval, close the review issue manually; the sweep only enumerates open PRs.

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

Multica has no git-sync: agent instructions and skills live server-side, and this repo is the desired state. `scripts/sync-multica.sh` is the bridge — for every profession directory under `agents/`:

- `agents/<role>/skill.md` → `multica skill update` (create when the skill is absent)
- `agents/<role>/personality.md` → `multica agent update --instructions` (the `engineer` role fans out to both instances, Engineer-A and Engineer-B)

```bash
scripts/sync-multica.sh                    # dry run, all roles — prints commands + summary, writes nothing
scripts/sync-multica.sh --agent ceo        # dry run, one role
scripts/sync-multica.sh --apply            # execute, all roles
scripts/sync-multica.sh --apply --agent engineer
```

Dry-run is the default; only `--apply` writes. Auth is ambient (`multica login` / `MULTICA_SERVER_URL` / `MULTICA_WORKSPACE_ID`) — the script never reads, stores, or embeds tokens, and it fails loud when the `multica` CLI is missing. Naming follows convention ("CEO Skill", agent display names) with `SYNC_SKILL_<ROLE>` / `SYNC_AGENT_<ROLE>` env overrides when server naming differs. Agent creation and model/runtime changes are deliberately out of scope: an unmapped agent fails the run with instructions, and desired models per role are documented in the Roster table above — append `--model` / `--runtime-id` to the printed `multica agent update` command manually.

## Do Not

- Do not introduce a shared `skills/` folder. Each agent owns its full skill content.
- Do not overwrite team-specific template content (roster, routing preamble) from upstream — it is canonical in this repo; only the generic section skeleton mirrors `stone16/harness-template`.
- Do not introduce a new profession without an entry in the Roster table and a corresponding `agents/<role>/` folder with both files, then a re-sync.
- Do not let anyone but the CEO @-mention an agent, and the CEO only in delegation comments. Members' delivery comments are mention-free — that is what returns control to the leader and what keeps mention cycles structurally impossible.
- Do not dispatch work without an inline DoD block, and do not close a step whose delivery has not addressed every `dod.evidence` item.
- Do not commit a sentinel-writing change without updating `agents/engineer/skill.md` AND `agents/evaluator/skill.md` plus `tests/pr-sweep.test.sh`, then syncing to Multica — sentinel formats must stay in lock-step.
- Do not commit operational identity: agent UUIDs, mention links, workspace ids, tokens, or private repo names belong in GitHub Actions secrets/variables, not tracked files.
- Do not hand-edit agent instructions or skills on the Multica server without landing the change in this repo first. `scripts/sync-multica.sh` treats this repo as the source of truth and will overwrite server drift.
