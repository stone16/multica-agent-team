## Auto-Harness

If you are a Multica code-shipping agent (an Engineer instance)
and you were just assigned an `impl`-label issue, read this BEFORE writing any production
code. Auto-harness gates large tasks behind a two-stage flow.

### Stages

- **Stage 1 (Codex, local) — done by an Engineer instance in Codex, NOT by you as the assignee.** Contested spec or architecture decisions are adjudicated by the Orchestrator.
  Runs `harness-engineering-skills:harness` to (1) assess whether the change fits the
  current scale and (2) draft logic + checkpoints. Output: `.harness/<task-id>/spec.md`
  inside the target repo's worktree. The spec is *not* committed; it lives on the local
  filesystem only.
- **Stage 2 (Multica, you) — execute checkpoints, run E2E, retro.**

Your job is to detect which stage the issue is in and act accordingly.

### Stage Gate (run on every assigned `impl` issue)

1. Determine the task ID. Default = the issue identifier (e.g. `STO-46`) lowercased.
   If the issue body has a literal line `harness task-id: <name>`, use that instead.

2. Determine the target repo. Inspect the issue body for a repo URL or
   `repo: <name>`; otherwise default to the project's primary repo.

3. Check for the spec on disk:
   ```
   test -f <repo>/.harness/<task-id>/spec.md && echo OK || echo MISSING
   ```

4. Branch:
   - **Spec found** → go to "Execute Stage 2".
   - **Spec missing** → go to "Pre-flight Budget Check".

### Pre-flight Budget Check (only when no spec exists)

Safety net for tasks the user assigned directly to you, skipping Stage 1. Compute
these signals from the issue body and a quick grep over the planned scope:

| Signal | Threshold | How to estimate |
|---|---|---|
| Net code change (added + modified, excl. tests/docs/lockfiles) | ≥ 500 LOC | grep + wc on planned files; if you cannot estimate, treat as tripped |
| Distinct production files touched | ≥ 8 | file list from issue or pre-flight grep |
| Distinct top-level modules touched | ≥ 3 | path prefix grouping |
| Touches LLM call site / prompt / eval / model-routing | any occurrence | grep `anthropic\|openai\|deepseek\|prompt\|eval/` over planned diff scope |
| Adds new external dependency | any | `git diff base -- go.mod package.json requirements.txt` |
| Touches migration / schema / daemon / supervisor | any | path match on `migrations/ schema/ daemon/ supervisor/` |

Always post the budget table, even if nothing trips:

```
[auto-harness: budget]

| Signal | Estimate | Tripped |
|---|---|---|
| Net LOC | <n> | yes/no |
| Files touched | <n> | yes/no |
| Modules touched | <n> | yes/no |
| LLM-touching | yes/no | yes/no |
| New dependency | yes/no | yes/no |
| Migration/daemon | yes/no | yes/no |

Verdict: bounce-to-stage-1 | proceed-direct
```

If **any** signal trips → bounce. Post the bounce-back comment below, set status
`blocked`, exit silently.

If **none** trip → proceed with normal agent flow (write code → PR).

### Bounce-back Comment

When the budget trips and there is no Stage-1 spec, post this comment verbatim
(filling the `<signal>` and `<repo-path>` placeholders), then set status
`blocked` and exit silently:

```
[auto-harness: bounce]

这个任务的复杂度超过我一次执行的预算（见上面的 budget 表，触发了 <signal>）。
请先在本地用 Codex 跑一下 Stage 1：

    cd <repo-path>
    # 在 Codex 里说："harness this task"，把这个 issue 的内容贴给它
    # 它会跑 brainstorm + spec evaluator，最后写到：
    #   <repo>/.harness/<task-id>/spec.md

写完以后把这个 issue 重新 assign 给我，我会读 spec 并把 checkpoint
拆成子 issue 执行下去。
```

### Execute Stage 2 (when spec is present)

1. Read `<repo>/.harness/<task-id>/spec.md`. Verify YAML frontmatter:
   - If `status: draft` → post `[auto-harness: spec-not-ready]` comment and exit.
   - Otherwise treat as approved.

2. Parse every `### Checkpoint NN: <title>` header. **Do NOT create or assign
   child issues yourself** — issue creation and assignment are CEO-owned
   dispatch under the constitution's DoD Dispatch Protocol. Instead, return a
   checkpoint PLAN in your delivery comment on the parent issue. Every checkpoint
   object must preserve an explicit native `stage` and the complete list of
   prerequisite checkpoint IDs in `depends_on`. Stage 1 has no dependencies;
   each later checkpoint's stage is one greater than the latest stage among its
   dependencies. If the spec does not define enough information to produce that
   graph, report `[auto-harness: checkpoint-plan-invalid]` and the ambiguity;
   never omit or guess either field.

   [auto-harness: checkpoint-plan]

   Spec: <repo>/.harness/<task-id>/spec.md
   Proposed children (for CEO dispatch; the fenced JSON array is authoritative):

   ```json
   [
     {
       "id": "cp-01",
       "title": "Produce prerequisite artifact",
       "stage": 1,
       "depends_on": [],
       "body": "The checkpoint's Scope, Acceptance Criteria, and Verification Commands inlined verbatim from the spec.",
       "suggested_dod": {
         "outcome": "The prerequisite artifact is accepted.",
         "evidence": "Verification output and artifact link.",
         "verification": "evaluator",
         "max_rounds": 2
       }
     },
     {
       "id": "cp-02",
       "title": "Consume prerequisite artifact",
       "stage": 2,
       "depends_on": ["cp-01"],
       "body": "The dependent checkpoint's Scope, Acceptance Criteria, and Verification Commands inlined verbatim from the spec.",
       "suggested_dod": {
         "outcome": "The dependent behavior is accepted.",
         "evidence": "Verification output proving the prerequisite was consumed.",
         "verification": "evaluator",
         "max_rounds": 2
       }
     }
   ]
   ```

   Suggested implementation roles are advisory: the child is owned by the
   parent's exact Squad, whose leader chooses an Engineer instance and the
   required Evaluator lane(s). Vertical tiers are abolished; do not route by
   perceived difficulty.

3. The **CEO** validates the authoritative JSON graph before creating any child,
   then creates and dispatches every child issue with the validator's exact
   stage/status result. The child description must begin with the validated
   `Checkpoint ID: <id>`, `Stage: <N>`, and
   `Depends on: <comma-separated IDs | none>` header so the dependency identities
   remain queryable after creation:

   ```bash
   python3 <orchestrator-skill-dir>/scripts/validate-checkpoint-plan.py ./checkpoint-plan.json

   multica issue create \
     --title "[harness:cp-NN] <checkpoint title>" \
     --description-stdin \
     --parent <parent-issue-id> \
     --stage <validated stage> \
     --status <validated status> \
     --assignee-id <exact owning Squad UUID>
   multica issue label add <child-id> <harness:cp label-id>
   ```

   Every child body uses `templates/squad-issue.md`, including its owning Squad,
   stable correlation ID, result contract, verification, evidence, work graph,
   freshness, rework, and fallback sections. Every leader dispatch carries an inline `dod:` block
   (`outcome` / `evidence` / `verification` / `max_rounds`) per the DoD
   Dispatch Protocol — the CEO may adjust the suggested fields, but no child
   issue is dispatched without one. The CEO then posts the dispatch comment
   on the parent:

   ```
   [auto-harness: dispatch]

   Spec: <repo>/.harness/<task-id>/spec.md
   Dispatched checkpoints:
   - cp-01 → [STO-NNN](mention://issue/<id>) → owning Squad
   - cp-02 → [STO-NNN](mention://issue/<id>) → owning Squad
   - ...

   Native stage barriers will wake the parent after each runnable frontier closes.
   ```

4. After posting the checkpoint plan, set parent status `in_review`. Exit
   silently; dispatch is the CEO's move, not yours.

### E2E Dispatch (after the checkpoint stage barrier closes)

A checkpoint child counts as closed ONLY when its status is `done` AND, where
its `dod` specified `verification: evaluator`, the Evaluator's verification
verdict is PASS. `in_review` is explicitly NOT closed — a child awaiting
evaluator verification still blocks this step. Do not propose the E2E child
while any checkpoint fails that bar.

You do not self-trigger this step. Only `done` and `cancelled` close the native
checkpoint barrier; `blocked` holds it open. On the native barrier wake, the CEO
reads `multica issue children`, verifies the acceptance bar above, and posts a
dispatch on the PARENT issue @-mentioning you, the proposing Engineer, with a
DoD whose `outcome` is the `[auto-harness: e2e-plan]` delivery. Native wake does
not promote later work automatically. On that dispatch, propose exactly one E2E
child in a comment on the parent — do not create it yourself:

```
[auto-harness: e2e-plan]

Proposed child (for CEO dispatch): [harness:e2e] End-to-end verification for <parent title>
suggested dod:
  outcome: parent spec's `## Verification` commands re-run holistically and
    the user-visible golden path exercised end-to-end
  evidence: command output and golden-path evidence per the Engineer's
    `## Verification Matrix` and `## AI-Aware Engineering` rules
  verification: evaluator
  max_rounds: 2
```

The **CEO** creates the child issue parked in the later stage, then promotes it
to `todo` after the checkpoint barrier wake and dispatches it with an inline
`dod:` block (`outcome` / `evidence` / `verification` / `max_rounds`):

```bash
multica issue create \
  --title "[harness:e2e] End-to-end verification for <parent title>" \
  --description-stdin \
  --parent <parent-issue-id> \
  --stage <checkpoint stage + 1> \
  --status backlog \
  --assignee-id <exact owning Squad UUID>
multica issue label add <e2e-id> <harness:e2e label-id>
```

E2E ownership remains with the parent's exact Squad using
`templates/squad-issue.md`; the leader activates an **Engineer instance** for
execution and the declared Evaluator lane afterward.

### Retro (after E2E child closes)

Post the retro comment on the parent issue:

```
[auto-harness: retro]

Outcome: <one-line summary>
Checkpoints: <count> dispatched, <count> passed, <count> required iteration
Wall-clock: <duration> from auto-harness:dispatch to E2E close
Lessons: <bullets — what should the next auto-harness run remember>
```

If the retro identifies actionable problems (drift between spec and implementation,
broken budget heuristic, missing template, etc.), **file a follow-up GitHub issue in
the `harness-engineering-skills` repo** (`gh issue create -R stone16/harness-engineering-skills ...`)
— that repo is the canonical home for harness retros and convention gaps. Also
write the retro markdown to `harness-engineering-skills/.harness/retro/<date>-<task-id>.md`
per existing convention there.

Keep the parent in `in_review`; do not change status here. The CEO then runs its Retro close-out step: after the retro delivery passes the DoD check, the CEO runs the Orchestrator skill's Deterministic Parent Close Sequence (correlation marker lookup/result comment → verified metadata → Squad activity → status). No auto-harness path changes the parent status directly. Stop.

### Label bootstrap (one-time per workspace)

If `multica label list` does not include `harness:cp` and `harness:e2e`, create
them once and reuse:

```
multica label create --name "harness:cp"  --color "#7B61FF"
multica label create --name "harness:e2e" --color "#00C4B4"
```

Both label IDs and the matching title prefix (`[harness:cp-NN]`, `[harness:e2e]`)
are applied — title prefix is the human-readable signal, label is the machine
filter for sweep / autopilot scripts.

### Failure modes to avoid

- Skipping the stage gate because "I already know there's a spec." Run the file
  test. The check is the gate.
- Posting the budget table but writing code anyway when something tripped. Bounce.
- Dispatching checkpoints without `parent_issue_id`. Without it, the audit trail
  breaks.
- Tagging another agent in any `[auto-harness: ...]` comment. Never. Members
  post comments with no mentions; the CEO routes on re-trigger.
- Editing `<repo>/.harness/<task-id>/spec.md` from Multica. The spec is Stage 1's
  artifact, not yours. If the spec is wrong, post a `TODO_DECISION:` and bounce
  back to Stage 1 — do not silently rewrite the spec mid-execution.
- Running E2E inside the parent run instead of dispatching it as a child issue.
  E2E must be a fresh Engineer-instance run (anti-drift), never reused context
  from the checkpoint runs.
