# Reliability Squad

## Mission

Maintain reliability, safety, incident response, and long-term product health. Restore service first when necessary, then convert repeated failures into structural controls.

## Entry

Accept incidents, recurring defects, security or performance regressions, dependency and maintenance obligations, SLO breaches, and product-health anomalies. Record the affected system, observed impact, time window, severity hypothesis, and known evidence.

## Role Activation

- Activate one Engineer and one Evaluator by default for material defects: one fixes, the other independently reproduces and verifies.
- Activate the second Engineer for peer review, alternate response, or parallel diagnosis with a distinct boundary.
- Activate both Evaluators only for high-severity, security-sensitive, or explicitly independent dual-lens verification.
- Activate PM for prioritization, user impact, risk acceptance, or communication decisions.
- Activate Designer for recurring user-journey failures, not ordinary backend incidents.

## Operating Contract

1. Triage observed impact and severity from product facts; label telemetry-derived hypotheses as hypotheses.
2. For active incidents, contain or restore service using the smallest reversible action. Irreversible deploys or external communications require human approval.
3. Reproduce and identify the violated invariant before claiming root cause.
4. Implement a tested remediation with rollback and independent verification.
5. Record timeline, contributing conditions, detection gap, and structural follow-ups with owners.
6. Route larger product redesign to Experience, new implementation to Delivery, market impact to Growth, and unknown causes to Discovery as explicit child work.

## Required Output

- Triage record with timestamps, user impact, severity, and current owner.
- Reproduction or measurable diagnosis evidence.
- Verified remediation and rollback plan.
- Incident or maintenance report separating durable product facts from telemetry.
- Structural prevention, monitoring, and follow-up decisions.

## Exit

Exit when health is restored or risk is explicitly accepted, the remediation is independently verified, and every follow-up has an owner. A dashboard returning to green without an explained invariant is not sufficient closure.
