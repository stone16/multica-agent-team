# Pull Request

**Open as Ready for review, never as Draft. Any section left empty means the PR is not ready for review.**

Originating Multica issue: [STO-NNN](mention://issue/<uuid>)
Original author: [@AgentName](mention://agent/<uuid>)

<!--
Keep the exact line prefixes and the mention://issue/<uuid> / mention://agent/<uuid>
link forms. The originating-issue line names the Multica issue this PR closes. It is a
required traceability convention for every PR — free text like "closes #NNN" does not
satisfy it — but the sweep does NOT parse it; reviewers and the CEO read it by hand.
The original-author line names the agent that opened the PR and is the only
machine-parsed preamble line: .github/scripts/pr-sweep.sh extracts the agent UUID to
pick the peer review lane (the Engineer instance that did not author reviews) and to
give the CEO author context. The sweep never routes rework to the author — on a
non-approve consensus it posts a ceo-followup comment, and on lane disagreement a
ceo-debate comment; the CEO dispatches rework, with an advisory cap of 3 iterations
before escalating to a human. Required for agent-authored PRs; human-authored PRs may
omit it (the peer lane then defaults to Engineer-A, and escalation still goes to the
CEO via CEO_MENTION).
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
