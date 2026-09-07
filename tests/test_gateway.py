#!/usr/bin/env python3
"""Contract tests for the portable Gateway boundary."""

from __future__ import annotations

import unittest

from scripts.gateway import GatewayError, GatewayHandler, GatewayRequest
from scripts.retry_policy import RETRY_INTERVAL, decide_retry


class FakeClient:
    def __init__(self, targets=None):
        self.targets = targets or []
        self.calls = []

    def list_targets(self, target_type):
        self.calls.append(("list", target_type))
        return [target for target in self.targets if target["type"] == target_type]

    def create_issue(self, *, title, description, assignee_id):
        self.calls.append(("create", title, description, assignee_id))
        return {"identifier": "INIT-1", "assignee_id": assignee_id}

    def get_issue(self, identifier):
        self.calls.append(("get", identifier))
        return {"identifier": identifier, "status": "in_progress", "assignee_type": "squad", "assignee_id": "s1"}

    def add_issue_comment(self, identifier, content):
        self.calls.append(("comment", identifier, content))

    def rerun_issue(self, identifier):
        self.calls.append(("rerun", identifier))


class GatewayContractTests(unittest.TestCase):
    def setUp(self):
        self.client = FakeClient([{"type": "squad", "id": "s1", "name": "Discovery"}])
        self.handler = GatewayHandler(self.client, {"routes": {"discovery": {"type": "squad", "name": "Discovery"}}})

    def test_dispatch_preserves_request_and_thread_context(self):
        result = self.handler.handle(
            GatewayRequest(user_text="Find the target user", intent="discovery"),
            thread_context="Slack source: slack:thread-1",
        )

        self.assertEqual(result, "INIT-1")
        create = self.client.calls[-1]
        self.assertEqual(create[0], "create")
        self.assertIn("Find the target user", create[2])
        self.assertIn("Slack source: slack:thread-1", create[2])

    def test_unknown_intent_fails_before_remote_lookup(self):
        with self.assertRaisesRegex(GatewayError, "unknown intent"):
            self.handler.handle(GatewayRequest(user_text="x", intent="unknown"))
        self.assertEqual(self.client.calls, [])

    def test_duplicate_target_fails_closed(self):
        client = FakeClient([
            {"type": "squad", "id": "s1", "name": "Discovery"},
            {"type": "squad", "id": "s2", "name": "Discovery"},
        ])
        with self.assertRaisesRegex(GatewayError, "exactly one"):
            GatewayHandler(client, self.handler.policy).handle(
                GatewayRequest(user_text="x", intent="discovery")
            )

    def test_answer_creates_no_issue(self):
        result = self.handler.handle(GatewayRequest(user_text="hello", intent="answer"))
        self.assertEqual(result, "")
        self.assertEqual(self.client.calls, [])

    def test_retry_retriggers_existing_issue(self):
        result = self.handler.handle(GatewayRequest(user_text="retry INIT-1", intent="retry"))
        self.assertEqual(result, "INIT-1")
        self.assertEqual(self.client.calls, [("get", "INIT-1"), ("rerun", "INIT-1")])

    def test_request_requires_nonempty_text_and_intent(self):
        with self.assertRaisesRegex(GatewayError, "user_text"):
            GatewayRequest.from_mapping({"user_text": "", "intent": "discovery"})
        with self.assertRaisesRegex(GatewayError, "intent"):
            GatewayRequest.from_mapping({"user_text": "x", "intent": ""})

    def test_timeout_schedules_retry_at_least_thirty_minutes_later(self):
        from datetime import datetime, timezone

        now = datetime(2026, 9, 7, 12, 0, tzinfo=timezone.utc)
        decision = decide_retry("request timeout", attempt=1, now=now)
        self.assertTrue(decision.retry)
        self.assertEqual(decision.retry_at, now + RETRY_INTERVAL)

    def test_503_schedules_retry_but_active_run_blocks_duplicate(self):
        from datetime import datetime, timezone

        now = datetime(2026, 9, 7, 12, 0, tzinfo=timezone.utc)
        self.assertTrue(decide_retry({"status": 503}, attempt=2, now=now).retry)
        decision = decide_retry(503, attempt=2, now=now, active_run=True)
        self.assertFalse(decision.retry)
        self.assertEqual(decision.reason, "active run already exists")

    def test_non_transient_error_does_not_schedule_retry(self):
        decision = decide_retry({"status": 400}, attempt=1)
        self.assertFalse(decision.retry)


if __name__ == "__main__":
    unittest.main()
