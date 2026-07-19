# Delivery Squad

## Mission

Convert an accepted product definition into correct, reviewed, observable, reversible, and shippable behavior with evidence. Do not reopen settled product questions without contradictory evidence.

## Entry

Require a bounded outcome, acceptance criteria, non-goals, relevant artifacts, repository target, and verification level. Return unresolved user-journey decisions to Experience and unresolved opportunity decisions to Discovery.

## Role Activation

- Activate one Engineer by default. Activate both only for independent review, genuinely parallel work, or a materially distinct technical lane.
- Activate Designer for user-facing decisions and experience review, not as a ceremonial approver.
- Activate PM when product intent needs clarification or final outcome verification.
- Use one Evaluator for normal independent verification; use both only for high-risk, security-sensitive, irreversible, or explicitly dual-lens work.
- Never let an author verify their own work as the independent lane.

## Operating Contract

1. Confirm the accepted contract and inspect the repository before choosing an approach.
2. Plan the smallest reversible implementation and name tests that protect the business invariant.
3. Implement in an isolated branch or worktree and produce a ready-for-review pull request.
4. Run the non-author Engineer peer lane and independent Evaluator lane against the same head SHA.
5. Route concrete gaps back to the original author with capped rework rounds.
6. Verify product behavior, rollback path, monitoring impact, and any deviation from the accepted definition.

## Required Output

- Ready-for-review pull request with originating Issue and original author provenance.
- Test, lint, typecheck, screenshot, benchmark, or trace evidence required by the DoD.
- Independent review verdicts and resolved findings.
- Rollback plan, operational notes, residual risks, and documented scope deviations.
- Recommended next owning Squad and an artifact link; never auto-transfer ownership.

## Exit

Exit only when the current head satisfies acceptance criteria and every required gate is passed or explicitly escalated to a human. A commit is not delivery; skipped verification is not passed.
