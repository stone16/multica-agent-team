#!/usr/bin/env python3
"""Deterministic promotion and rollback state transitions for CI adapters."""
from __future__ import annotations
from enum import StrEnum

class PromotionState(StrEnum):
    REQUESTED = "requested"
    CHECKING = "checking"
    AWAITING_APPROVAL = "awaiting_approval"
    DEPLOYING = "deploying"
    HEALTHY = "healthy"
    ROLLING_BACK = "rolling_back"
    ROLLED_BACK = "rolled_back"
    FAILED = "failed"

class PromotionError(ValueError): pass

_ALLOWED = {
    PromotionState.REQUESTED: {PromotionState.CHECKING},
    PromotionState.CHECKING: {PromotionState.AWAITING_APPROVAL, PromotionState.FAILED},
    PromotionState.AWAITING_APPROVAL: {PromotionState.DEPLOYING, PromotionState.FAILED},
    PromotionState.DEPLOYING: {PromotionState.HEALTHY, PromotionState.ROLLING_BACK, PromotionState.FAILED},
    PromotionState.HEALTHY: set(),
    PromotionState.ROLLING_BACK: {PromotionState.ROLLED_BACK, PromotionState.FAILED},
    PromotionState.ROLLED_BACK: set(),
    PromotionState.FAILED: {PromotionState.ROLLING_BACK},
}

def transition(current: PromotionState | str, next_state: PromotionState | str) -> PromotionState:
    try:
        current, next_state = PromotionState(current), PromotionState(next_state)
    except ValueError as exc:
        raise PromotionError("unknown promotion state") from exc
    if next_state not in _ALLOWED[current]:
        raise PromotionError(f"invalid transition: {current} -> {next_state}")
    return next_state
