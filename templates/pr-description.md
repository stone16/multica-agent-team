# Pull Request Description Template

> This file is the **canonical source** for the PR description standard. `.github/PULL_REQUEST_TEMPLATE.md` is the minimum-threshold version shown to human contributors; this file is the full standard that code-shipping agents follow.

The unit of delivery is a Pull Request, not a commit. Code-shipping agents (CTO, Tech Lead, Senior Engineer, Junior Engineer) MUST use this template verbatim for every PR.

A PR description with any required section empty is a draft, not a request for review.
Open GitHub PRs as **Ready for review**, never as Draft PRs. If the body is not ready, do not open the PR yet. If GitHub creates the PR as draft anyway, run `gh pr ready` before handing it off.

---

## Summary

<one paragraph: what user-visible or API-visible state changes when this merges. Skip "implementation details" — those go in Approach. The reader should know after this section whether the change is relevant to them.>

## Why

<one paragraph: the user pain or constraint that justifies this change. Cite the issue: `closes #NNN` or link to the Multica issue. If there is no linked issue, state why the change is being made anyway — orphan PRs without a "why" are rejected.>

## Approach

<one or two paragraphs: how it was implemented.

- Modules / files touched (high level)
- Key design choices
- Alternatives rejected, with the constraint that ruled them out (mirror the Decision Format)
- Anything intentionally left for a follow-up issue, with a link>

## How I Tested

**For frontend changes (UI components, styles, browser-rendered behavior):**
- `### Before` — screenshot of the prior state (linked or embedded)
- `### After` — screenshot of the new state (linked or embedded)
- Numbered list of manual flows you walked through
- Browser + version where you tested
- Responsive / device matrix exercised, if applicable

**For backend changes (API contracts, data flow, scheduled jobs, daemon paths):**
- Table of end-to-end test cases, each citing the test `file:line`
- Verbatim output of running those tests (redact secrets, credentials, tokens, customer data, PII per the Evidence Preservation rule; use `<redacted: <kind>>` when redaction obscures diagnostic context)
- For new endpoints: a `curl` or `multica` CLI invocation showing the endpoint working end-to-end

**For any change:**
- Existing tests run: `<command>` → `<result>`
- New tests added: `<file:line>`, what they cover
- Lint / typecheck: `<command>` → `<result>`

A PR with no validation evidence in this section is rejected at first read.

## Rollback Plan

<how to revert: `git revert <merge-commit>`, feature flag toggle, schema rollback, etc. State two things explicitly:

1. **Maximum blast radius** of a wrong merge (zero / single feature / data integrity / cross-tenant — pick the most severe accurate label)
2. **Time-to-rollback** (under one minute / one deploy cycle / requires data migration — be honest)

If the rollback requires anything beyond `git revert`, list the steps in order.>

## Out of Scope

<bullet list of things this PR explicitly does NOT change. This defends against scope-creep review feedback and saves the reviewer from asking "why didn't you also...".>

---

## Worked Example — Frontend PR (How I Tested section only)

```
## How I Tested

### Before
![before](https://user-images.../before.png)

### After
![after](https://user-images.../after.png)

### Manual flows walked through
1. Open https://localhost:3000/issues, click "+" — modal opens within 100ms.
2. Type a 5-word title, press Enter — issue created, modal closes within 200ms, new issue appears at top of list.
3. Type empty input, press Enter — modal does not submit; inline error "Title required" appears.
4. Open in two browser tabs, type same title, submit simultaneously — both issues create, no duplicate id.

### Browser matrix
- macOS Chrome 134
- macOS Safari 17.5
- iOS Safari 17.4 (375×812 viewport)

### Existing tests
$ pnpm test issues
... 23 passed in 4.1s.

### New tests added
- `web/src/issues/QuickCreate.test.tsx:104` — empty-input submission is rejected with inline error.
- `web/src/issues/QuickCreate.test.tsx:128` — modal close time is < 200ms after Enter.

### Lint / typecheck
$ pnpm typecheck
ok

$ pnpm lint
ok
```

## Worked Example — Backend PR (How I Tested section only)

```
## How I Tested

### End-to-end test cases

| Case | Test file:line | What it asserts |
|---|---|---|
| Lock acquired by first writer | `server/internal/lock_test.go:42` | First task gets the row; second blocks |
| Second writer rejected with structured error | `server/internal/lock_test.go:67` | Returns 423 with `error_code: lock_contention` |
| Lock released on completion | `server/internal/lock_test.go:91` | `pg_locks` shows zero rows after task completes |
| Lock TTL expires after 30 min | `server/internal/lock_test.go:118` | Stuck task auto-releases at 30min mark |

### Verbatim test output

$ make test-backend
... 47 tests run (4 new), 47 passed in 12.3s.
PASS: TestAgentSkillLock_Contention
PASS: TestAgentSkillLock_StructuredError
PASS: TestAgentSkillLock_Release_Idempotent
PASS: TestAgentSkillLock_TTL_30min

### End-to-end with multica CLI

$ multica skill files upsert <skill-id> --path lessons.md --content "test"
HTTP 200, file written.

$ multica skill files upsert <skill-id> --path lessons.md --content "concurrent" &
$ multica skill files upsert <skill-id> --path lessons.md --content "concurrent2"
HTTP 423, {"error_code": "lock_contention", "retry_after_ms": 250}

### Existing tests
$ make test-backend
ok (output above)

$ make typecheck
ok

$ make lint
ok
```
