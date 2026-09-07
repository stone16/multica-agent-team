#!/usr/bin/env python3
"""Deterministic retry decisions for long-running Multica work."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Mapping


RETRY_INTERVAL = timedelta(minutes=30)
TRANSIENT_STATUS_CODES = frozenset({408, 425, 429, 500, 502, 503, 504})


@dataclass(frozen=True)
class RetryDecision:
    retry: bool
    reason: str
    retry_at: datetime | None = None


def _status_code(error: Any) -> int | None:
    if isinstance(error, int):
        return error
    if isinstance(error, Mapping):
        value = error.get("status") or error.get("status_code") or error.get("code")
        return value if isinstance(value, int) else None
    return None


def decide_retry(
    error: Any,
    *,
    attempt: int,
    now: datetime | None = None,
    active_run: bool = False,
) -> RetryDecision:
    """Return a scheduled retry decision without performing a remote write.

    A retry is scheduled only for an explicit transient HTTP code or a timeout
    signal. The caller must re-read the Issue before firing the scheduled retry;
    ``active_run`` makes the duplicate-run guard explicit at this boundary.
    """
    if attempt < 1:
        raise ValueError("attempt must be >= 1")
    if active_run:
        return RetryDecision(False, "active run already exists")

    code = _status_code(error)
    text = str(error).lower()
    timeout = "timeout" in text or "timed out" in text
    if code not in TRANSIENT_STATUS_CODES and not timeout:
        return RetryDecision(False, "error is not transient")

    current = now or datetime.now(timezone.utc)
    if current.tzinfo is None:
        raise ValueError("now must include a timezone")
    return RetryDecision(
        True,
        f"transient failure (status={code or 'timeout'}; attempt={attempt})",
        current + RETRY_INTERVAL,
    )
