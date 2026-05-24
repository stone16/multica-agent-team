# Architecture Spec

## Goal
Consensus `request-changes` and `block` PR reviews are adjudicated and resolved by the agent-team autopilot loop before they require Stometa to touch the PR.

## Context
The implementation belongs in `stone16/agent-team`, not `multica-ai/multica`: this repo owns the GitHub Action, shell orchestrator, and agent skill prompts for PR review automation. Today `.github/scripts/pr-sweep.sh` enumerates `stone16/*` PRs, parses reviewer sentinels from PR comments, creates or reuses one Multica review issue per PR, and dispatches Hao/Dustin through that issue (`.github/scripts/pr-sweep.sh:44`, `.github/scripts/pr-sweep.sh:88`, `.github/scripts/pr-sweep.sh:117`, `.github/scripts/pr-sweep.sh:328`). The workflow already runs every 15 minutes and uses the Multica CLI plus GitHub PAT from this repo's Actions secrets (`.github/workflows/pr-sweep.yml:7`, `.github/workflows/pr-sweep.yml:26`). The missing arc is after both reviewers agree on `request-changes` or `block`: the script currently posts `Action: cto-followup`, assigns Stometa, and asks for discussion (`.github/scripts/pr-sweep.sh:278`, `.github/scripts/pr-sweep.sh:291`, `.github/scripts/pr-sweep.sh:370`, `.github/scripts/pr-sweep.sh:416`). Double approve already closes the review issue and writes the deterministic consensus sentinel (`.github/scripts/pr-sweep.sh:413`, `.github/scripts/pr-sweep.sh:421`).

## Proposed Design
Keep `agent-team` as the only code and prompt home. The Multica product repo is not part of this implementation; Multica is used through the existing autopilot surface: issue assignment, issue comments, `multica repo checkout`, and `multica issue` commands.

Replace the `cto-followup` branch with `fixer-followup` for same-verdict `request-changes` and `block`. The sweep remains the orchestrator: it posts the reconciled review bundle into the PR-owned Multica issue, assigns the configured fixer agent, and writes a per-SHA idempotency marker after the dispatch succeeds. CTO keeps `cto-debate` and any explicit human-decision ledger state. This is a reversible decision: the target agent is controlled by `FIXER_AGENT` and `FIXER_MENTION`, and the existing `cto-followup` behavior can be restored without changing reviewer sentinel format.

The fixer input source is the Multica review outcome comment produced by the sweep. That comment is canonical because `review_comment_body` already selects GitHub PR comments containing the exact reviewer sentinel and SHA, strips the sentinel, and copies the reviewer bodies into the PR-owned issue (`.github/scripts/pr-sweep.sh:254`, `.github/scripts/pr-sweep.sh:259`, `.github/scripts/pr-sweep.sh:275`, `.github/scripts/pr-sweep.sh:308`). The fixer may re-fetch GitHub PR comments for audit, but should not depend on a second parser.

The report landing for this checkpoint is the PR-owned Multica review issue. That is the durable surface already keyed from the PR thread through `<!-- multica-pr-review-issue: <issue-id> -->` (`.github/scripts/pr-sweep.sh:117`, `.github/scripts/pr-sweep.sh:122`, `.github/scripts/pr-sweep.sh:234`). Ace-wide or product UI summary remains outside this repo until Stometa chooses a final surface.

Reversible decision: if all findings are rejected and no code change is needed, the fixer pushes an explicit empty resolution commit. The next 15-minute sweep then sees a new head SHA and requests Hao/Dustin again. Rejected alternative: let the ledger alone mark the PR ready; that bypasses the existing approve stop signal. Rejected alternative: make the sweep re-trigger reviewers from ledger state without a new commit; that changes the cost model from commit-driven to state-driven.

## Data Model
No database migration and no new state store.

Existing PR comment markers stay unchanged:

- PR review issue mapping: `<!-- multica-pr-review-issue: <issue-id> -->`.
- Reviewer sentinels: `<!-- hao-reviewed: <sha> verdict: <approve|request-changes|block> -->` and `<!-- dustin-reviewed: <sha> verdict: <approve|request-changes|block> -->`.
- Final sentinels: `<!-- consensus: <sha> verdict: <v> -->` and `<!-- debate: <sha> -->`.

Add markers to comments in the same PR-owned Multica issue:

- Fixer request idempotency: `<!-- multica-fixer-requested: <sha> -->`.
- Per-finding ledger: `<!-- multica-finding: <original-sha> id: <stable-id> reviewer: <hao|dustin> state: <fixed|rejected|attempted-unconverged|needs-human-decision> commit: <sha|none> -->`.
- Fixer run summary: `<!-- multica-fixer-summary: <original-sha> verdict: <resolved|human-needed> followup: <new-head-sha|none> -->`.

Finding IDs are stable for the same original SHA. They are derived from original SHA, reviewer, cited `file:line`, and normalized finding text. The visible Markdown next to each marker must include source reviewer, source citation, state, reason, verification command/result, and commit link when present.

## Runtime Flow
1. The 15-minute GitHub Action runs `.github/scripts/pr-sweep.sh` from `stone16/agent-team`.
2. The sweep enumerates open PRs and skips PRs that already have a final sentinel for the current head SHA.
3. If neither reviewer has reviewed, the PR-owned Multica issue is assigned to Hao. If only one reviewer has reviewed, it is assigned to the other reviewer.
4. If Hao and Dustin both approve the same SHA, the current approve path remains unchanged: close the review issue and write `<!-- consensus: <sha> verdict: approve -->`.
5. If Hao and Dustin disagree, the current `cto-debate` path remains unchanged. CTO casts the deciding vote in the same PR-owned issue.
6. If Hao and Dustin agree on `request-changes` or `block`, the sweep posts `Action: fixer-followup`, assigns the configured fixer, and records `multica-fixer-requested`. The consensus sentinel is written only after the fixer request exists or was posted successfully, preserving the current dispatch-before-final-sentinel guard.
7. The fixer reads the outcome comment, fetches the current PR `headRefOid`, and checks out the exact original head SHA with `multica repo checkout https://github.com/<owner>/<repo>.git --ref <head-sha>`.
8. The fixer adjudicates each finding against full repo context. Reviewer identity is not evidence; the claim must be verified in code.
9. Valid findings are fixed, verified locally, committed, and pushed to the PR branch. Before pushing, the fixer re-checks that PR `headRefOid` still equals the original SHA. If it changed, the fixer stops and writes a stale-head note with no ledger.
10. Invalid findings are recorded as `rejected` with a concise reason. If all findings are rejected and no file changed, the fixer pushes an empty resolution commit.
11. Failed attempts are recorded as `attempted-unconverged`; product, architecture, or policy blockers are recorded as `needs-human-decision`.
12. The fixer posts one result comment containing all per-finding markers and one summary marker. A pushed follow-up commit naturally restarts Hao/Dustin review on the next sweep. The loop ends only when the reviewers write consensus approve.

## Observability
The script must log deterministic transitions without reviewer prose: `fixer-request=post|exists`, `fixer-summary=resolved|human-needed`, `fixer-stale-head`, and `fixer-dispatch-failed`. Fixer comments must include verification command names and pass/fail results. A summary renderer must be able to classify a PR from Multica issue markers alone: approved, waiting on reviewer pass for a new SHA, resolved by fixer and awaiting reviewer approve, or human-needed.

## Security
Reviewer prose is untrusted input. The fixer must not execute commands copied from review text unless they match repository scripts or package metadata. Use GitHub and Multica credentials only through `gh` and `multica`; never print tokens. Never force-push. Do not push to forks or protected branches unless `gh pr view` confirms the authenticated actor can update the PR branch. Do not assign the fixer to adjudicate its own reviewer findings. Mark uncertain authorization, policy, or branch-protection cases as `needs-human-decision`.

## Alternatives
- Commit docs/templates in `multica-ai/multica`: rejected because this workflow is owned by `stone16/agent-team`; Multica is the runtime platform accessed by CLI/autopilot, not the repo where the PR-sweep behavior lives.
- Keep CTO decision plus fixer execution: rejected because it preserves the human touch on every non-approve consensus, which is the cost this issue is trying to remove.
- Create a separate service or queue: rejected because the existing PR-owned Multica issue, GitHub sentinels, and scheduled shell sweep already provide idempotent routing and convergence.
- Use GitHub PR comments as the worker's primary input: rejected because the sweep already normalizes exact-SHA reviewer bodies into the PR-owned Multica issue; duplicating that parser increases drift.
- Let the fixer write final approve sentinels: rejected because Hao/Dustin consensus approve is the existing deterministic stop signal.

## Verification
Run these commands from `stone16/agent-team` after implementation:

```bash
bash -n .github/scripts/pr-sweep.sh
bash tests/pr-sweep.test.sh
rg -n "fixer-followup|multica-fixer-requested|multica-finding|attempted-unconverged|needs-human-decision" README.md agents .github/scripts tests docs
rg -n "^TODO_DECISION:" README.md .github/scripts tests docs
```

Expected assertions:

- Existing approve and debate behavior still passes.
- Consensus `request-changes` and `block` route to the fixer, not CTO.
- `cto-debate` still routes to CTO.
- `multica-fixer-requested` prevents duplicate fixer dispatch.
- Final PR sentinel is not written when fixer dispatch fails.
- A pushed fix commit or empty resolution commit causes the next sweep to request Hao/Dustin on the new SHA.
- Human-needed ledgers do not trigger duplicate fixer runs.

## Checkpoints

### Checkpoint 01: Document the fixer contract

- ID: cp-01
- Type: docs
- Effort: s
- Depends on: none

#### Scope
Update `README.md` and the relevant agent skills to describe the fixer-first follow-up path, the four-state ledger, and the preserved Hao/Dustin approve stop signal. Keep all docs in `stone16/agent-team`.

#### Acceptance Criteria
- README names `.github/scripts/pr-sweep.sh` as the orchestrator and states fixer work happens in the same PR-owned Multica issue.
- Reviewer/fixer instructions require exact head-SHA checkout before adjudication.
- The four states are documented with required evidence for each.
- Repo docs state that no implementation artifact belongs in `multica-ai/multica`.

#### Verification Commands
```bash
rg -n "fixer-followup|multica-finding|fixed|rejected|attempted-unconverged|needs-human-decision" README.md agents docs
rg -n "multica-ai/multica|stone16/agent-team" README.md docs
```

### Checkpoint 02: Route actionable consensus to fixer

- ID: cp-02
- Type: backend
- Effort: m
- Depends on: cp-01

#### Scope
Modify `.github/scripts/pr-sweep.sh` and `tests/pr-sweep.test.sh` so consensus `request-changes` and `block` post `Action: fixer-followup` in the existing PR review issue. Preserve approve close, debate escalation, per-SHA idempotency, and dispatch-failure safety.

#### Acceptance Criteria
- Consensus action items assign the configured fixer, not CTO.
- Debate still assigns CTO.
- `<!-- multica-fixer-requested: <sha> -->` prevents duplicate fixer requests.
- The PR consensus sentinel is written only after the fixer request is present or successfully posted.

#### Verification Commands
```bash
bash -n .github/scripts/pr-sweep.sh
bash tests/pr-sweep.test.sh
```

### Checkpoint 03: Add fixer worker instructions

- ID: cp-03
- Type: docs
- Effort: m
- Depends on: cp-02

#### Scope
Add or update the configured fixer agent skill with the runtime contract: read the outcome comment, verify head SHA, checkout by SHA, adjudicate each finding, push only verified commits, write the ledger, and avoid self-adjudicating reviewer comments.

#### Acceptance Criteria
- The fixer has an explicit trigger for `Action: fixer-followup`.
- The fixer refuses stale head SHAs before push.
- The fixer distinguishes all four states and knows when not to push.
- The fixer pushes an empty resolution commit only when all findings are rejected and no code changed.

#### Verification Commands
```bash
rg -n "Action: fixer-followup|multica repo checkout|headRefOid|allow-empty|attempted-unconverged|needs-human-decision" agents README.md docs
```

### Checkpoint 04: Persist and render the per-finding ledger

- ID: cp-04
- Type: backend
- Effort: m
- Depends on: cp-02 cp-03

#### Scope
Extend the issue-comment contract and tests so fixer result comments are machine-readable and human-readable. Keep the ledger in the PR-owned Multica review issue.

#### Acceptance Criteria
- Each reviewer finding has exactly one `multica-finding` marker for the original SHA in a fixer result comment.
- Fixed findings include a commit SHA and verification evidence.
- Rejected findings include a concise reason.
- `attempted-unconverged` and `needs-human-decision` classify the PR as human-needed.
- A summary renderer can produce three buckets from markers: processed PRs, no-current-human-action PRs, and human-needed PRs.

#### Verification Commands
```bash
bash tests/pr-sweep.test.sh
rg -n "multica-finding|multica-fixer-summary|human-needed|waiting reviewer" .github/scripts tests README.md docs
```

### Checkpoint 05: Prove the end-to-end loop

- ID: cp-05
- Type: infra
- Effort: m
- Depends on: cp-01 cp-02 cp-03 cp-04

#### Scope
Exercise the loop with test stubs and one non-production test PR if available. Do not require a production repo merge.

#### Acceptance Criteria
- Seeded non-approve reviewer sentinels produce one fixer request.
- A fixer result with a pushed follow-up commit causes the next sweep to request Hao/Dustin for the new SHA.
- A human-needed fixer result does not produce duplicate fixer requests.
- Double approve on the follow-up SHA marks the review issue done.

#### Verification Commands
```bash
bash tests/pr-sweep.test.sh
gh pr view <test-pr-number> --repo stone16/<test-repo> --json headRefOid,headRefName,headRepositoryOwner
multica issue comment list <review-issue-id> --recent 20 --output json
```
