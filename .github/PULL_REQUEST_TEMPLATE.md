# Pull Request

**Open as Ready for review, never as Draft. Any section left empty means the PR is not ready for review.**

Originating Multica issue: [STO-42](mention://issue/<uuid>)
Original author: [@AgentName](mention://agent/<uuid>)

<!--
The two routing-preamble lines above are machine-parsed by .github/scripts/pr-sweep.sh.
- Originating Multica issue: required for every PR. The literal mention://issue/<uuid> form
  is mandatory; free text like "closes #NNN" or "see Multica" does NOT satisfy the parser
  and the PR-review loop will block on it.
- Original author: required for agent-authored PRs (the loop pings this agent when reviewers
  request changes, for up to 3 iterations before escalating to a human). Human-authored PRs
  may delete this line; the loop will fall back to escalating directly to the workspace owner.
-->

## Summary

<one paragraph: what user-visible or API-visible state changes when this merges>

## Why

<one paragraph: the user pain or constraint that justifies this change. Cite the issue: closes #NNN or the Multica issue link>

## Approach

<one or two paragraphs: how it was implemented. Name modules touched, key design choices, alternatives rejected with the constraint that ruled them out, and anything intentionally deferred>

## How I Tested

<for frontend changes: include ### Before / ### After screenshots, numbered manual flows, browser matrix>

<for backend changes: include end-to-end test case table with test file:line, verbatim test output redacted as needed, and curl or multica CLI evidence for new endpoints>

<for any change: include existing tests run, new tests added with file:line, and lint/typecheck output>

A PR with no validation evidence in this section is rejected at first read.

## Rollback Plan

<how to revert. State two things explicitly:

1. **Maximum blast radius** of a wrong merge (zero / single feature / data integrity / cross-tenant — pick the most severe accurate label)
2. **Time-to-rollback** (under one minute / one deploy cycle / requires data migration — be honest)

If rollback requires anything beyond `git revert`, list the steps in order.>

## Out of Scope

- <thing this PR explicitly does not change>
