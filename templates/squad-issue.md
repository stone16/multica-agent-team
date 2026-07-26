# Squad Issue Contract

## Owning Squad

<Discovery | Experience | Delivery | Growth | Reliability>

## Outcome

<One observable state that counts as complete.>

## Context and Evidence

<Current facts, dated sources, linked artifacts, and relevant prior decisions.>

## Acceptance Criteria

- <Observable criterion>

## Non-Goals

- <What this run must not change or decide>

## Scope and Target

<Repository, product surface, users, systems, or decision boundary in scope.>

## Verification

`self | evaluator | dual_evaluator | human`

## Evidence Required

- <Tests, screenshots, links, measurements, cited artifacts, or approvals>

## Rework Cap

`max_rounds: 2`

## Leader Entry Fallback

If the primary Squad leader fails before tool execution because its runtime, provider, authentication, or quota is unavailable, inspect the threaded and system failure comments and reroute steering to the Squad's declared `fallback_leader`. Keep the same owning Squad and contract. This pre-execution failover does not consume a rework round.
