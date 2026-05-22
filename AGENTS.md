# AGENTS.md

Repo-wide agent rules.

## Scope & Grounding

State assumptions explicitly. Ask one clarifying question when ambiguity changes the implementation path, target, or deliverable. Do not ask when the uncertainty can be resolved by reading files or running safe commands.

Define success criteria before multi-step work or any code change. State what "done" looks like and the verification commands. Loop until verified against that criteria.

Checkpoint after each significant step. Summarize what was done, what is verified, and what is left. If you lose track, stop and restate.

## Verification & Evidence

Use evidence. When making a claim about repository behavior, cite a file path and line number or say it is a hypothesis.

Never fabricate command output. Run the command, preserve the important output, and state clearly when a command cannot be run.

Read before you write. Before adding code in a file, read its exports, immediate callers, and shared utilities. "Looks orthogonal" is the most dangerous assumption — if unsure why code is structured a certain way, ask.

Tests must verify intent, not just behavior. Every test must encode the business invariant it protects. A test that still passes after the meaningful business rule changes is shallow.

Never claim completion if anything was skipped or unverified. Default to surfacing uncertainty, not hiding it.

Separate product facts from telemetry. Logs, traces, and metrics help diagnose behavior; durable product state belongs in ledgers.

## Code Discipline

Simplicity first. Do not add abstractions, configuration, feature flags, new dependencies, or generalized helpers unless the current task needs them more than once. Minimum code that solves the problem.

Surgical changes. Touch only what the task requires. Do not "improve" adjacent code, comments, or formatting. Clean up only your own mess. Match existing style.

Match codebase conventions, even when you disagree. Conformance beats taste inside the codebase. If you think a convention is harmful, surface it as a separate discussion — do not fork it silently.

When codebase patterns conflict, choose the more recent, more tested, or more locally dominant pattern. State which constraint made the choice true. Flag the other pattern for cleanup. Do not blend conflicting patterns.

Use the model for judgment over ambiguous or unstructured input. Classification, summarization, extraction from unstructured text — yes. Routing, retries, validation, counting, sorting, parsing structured data, status-code handling — write code instead.

Do not lock implementation details too early. Framework presets are allowed, but the core loop must remain portable.
