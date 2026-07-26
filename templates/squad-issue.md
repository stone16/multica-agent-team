# Squad Issue Contract

## Owning Squad

<Discovery | Experience | Delivery | Growth | Reliability — assign by exact Squad UUID>

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

## Correlation ID

<Caller-provided stable value. The Squad echoes it unchanged in `correlation_id` metadata.>

## Result Contract

The Squad posts one consolidated parent result comment and then indexes it with:

- `squad_verdict`: `delivered | inconclusive | blocked | escalated`
- `squad_result_comment_id`: UUID of that consolidated comment
- `squad_next_owner`: exact Squad name or `none`
- `squad_evidence_complete`: boolean
- `correlation_id`: the value above, unchanged

Metadata is an index only. The long result remains in the pointed-to comment; `runs[].result.output` is not the final deliverable.

## Verification

`self | evaluator | dual_evaluator | human`

## Evidence Required

- <Tests, screenshots, links, measurements, cited artifacts, or approvals>

## Work Graph

<Use staged child issues for dependencies, independent acceptance, retry/cancel boundaries, or queryable work. Stage 1 is `todo`; later stages start `backlog`. Use comment fan-out only for small context-sharing analysis.>

## Freshness Window

<Caller-configured duration without new run-message events that counts as stalled. Total elapsed runtime alone does not.>

## Rework Cap

`max_rounds: 2`

## Entry Failure and Fallback

No fallback is assumed. A fallback is eligible only when it is a separate Orchestrator identity, deployed and added to every affected Squad, and a fresh topology verify proves that exact topology. A transient failure may rerun the current Squad assignment; otherwise escalate sustained provider/runtime/auth/quota failure with evidence.
