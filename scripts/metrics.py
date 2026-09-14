#!/usr/bin/env python3
"""Open, provider-neutral metrics events and promotion safety decisions."""
from __future__ import annotations
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Mapping

class MetricsError(ValueError):
    pass

@dataclass(frozen=True)
class MetricEvent:
    name: str
    occurred_at: str
    service: str
    environment: str
    run_id: str
    status: str
    evidence: tuple[str, ...] = ()
    extensions: Mapping[str, Any] = None

    @classmethod
    def from_mapping(cls, value: Mapping[str, Any]) -> "MetricEvent":
        required = ("name", "occurred_at", "service", "environment", "run_id", "status")
        if not isinstance(value, Mapping) or any(not isinstance(value.get(k), str) or not value[k].strip() for k in required):
            raise MetricsError("event requires non-empty name, occurred_at, service, environment, run_id, status")
        try:
            parsed = datetime.fromisoformat(value["occurred_at"].replace("Z", "+00:00"))
        except ValueError as exc:
            raise MetricsError("occurred_at must be ISO-8601") from exc
        if parsed.tzinfo is None:
            raise MetricsError("occurred_at must include timezone")
        evidence = value.get("evidence", ())
        if not isinstance(evidence, (list, tuple)) or any(not isinstance(item, str) or not item for item in evidence):
            raise MetricsError("evidence must be a list of non-empty strings")
        reserved = set(required) | {"evidence", "extensions"}
        extensions = value.get("extensions", {})
        if not isinstance(extensions, Mapping):
            raise MetricsError("extensions must be an object")
        # Unknown top-level fields are preserved as extensions so new services remain forward compatible.
        merged = dict(extensions)
        merged.update({k: v for k, v in value.items() if k not in reserved})
        return cls(*(value[k].strip() for k in required), tuple(evidence), merged)

def promotion_allowed(*, checks_passed: bool, human_approved: bool) -> bool:
    return checks_passed and human_approved

def rollback_required(*, deploy_failed: bool, health_failed: bool, regression: bool) -> bool:
    return deploy_failed or health_failed or regression
