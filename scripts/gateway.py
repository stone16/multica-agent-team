#!/usr/bin/env python3
"""Portable, deterministic boundary between natural requests and Multica Issues.

The model may choose an intent. This module owns validation, target resolution,
context preservation, and repeatable Issue controls.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, Mapping, Protocol


class GatewayError(ValueError):
    """A request cannot be safely routed."""


class GatewayClient(Protocol):
    def list_targets(self, target_type: str) -> list[Mapping[str, Any]]: ...
    def create_issue(self, *, title: str, description: str, assignee_id: str) -> Mapping[str, Any]: ...
    def get_issue(self, identifier: str) -> Mapping[str, Any]: ...
    def add_issue_comment(self, identifier: str, content: str) -> None: ...
    def rerun_issue(self, identifier: str) -> None: ...


@dataclass(frozen=True)
class GatewayRequest:
    user_text: str
    intent: str

    @classmethod
    def from_mapping(cls, value: Mapping[str, Any]) -> "GatewayRequest":
        user_text = value.get("user_text")
        intent = value.get("intent")
        if not isinstance(user_text, str) or not user_text.strip():
            raise GatewayError("user_text must be a non-empty string")
        if not isinstance(intent, str) or not intent.strip():
            raise GatewayError("intent must be a non-empty string")
        return cls(user_text=user_text.strip(), intent=intent.strip().lower())


ISSUE_PATTERN = re.compile(r"\b([A-Z][A-Z0-9]+-\d+)\b")


class GatewayHandler:
    def __init__(self, client: GatewayClient, policy: Mapping[str, Any]):
        self.client = client
        self.policy = policy

    def handle(self, request: GatewayRequest, *, thread_context: str = "") -> str:
        if request.intent == "answer":
            return ""
        if request.intent in {"status", "continue", "retry"}:
            return self._control(request)
        routes = self.policy.get("routes")
        route = routes.get(request.intent) if isinstance(routes, Mapping) else None
        if not isinstance(route, Mapping):
            raise GatewayError(f"unknown intent: {request.intent}")
        target_type, target_name = route.get("type"), route.get("name")
        if target_type not in {"agent", "squad"} or not isinstance(target_name, str):
            raise GatewayError(f"invalid route for intent: {request.intent}")
        targets = [
            target for target in self.client.list_targets(target_type)
            if target.get("name") == target_name and isinstance(target.get("id"), str)
        ]
        if len(targets) != 1:
            raise GatewayError(f"route target must resolve to exactly one {target_type}: {target_name}")
        description = f"Original request:\n{request.user_text}"
        if thread_context.strip():
            description += f"\n\n{thread_context.strip()}"
        issue = self.client.create_issue(
            title=request.user_text,
            description=description,
            assignee_id=str(targets[0]["id"]),
        )
        identifier = issue.get("identifier")
        if not isinstance(identifier, str) or not identifier:
            raise GatewayError("Issue create returned no identifier")
        return identifier

    def _control(self, request: GatewayRequest) -> str:
        match = ISSUE_PATTERN.search(request.user_text.upper())
        if not match:
            raise GatewayError("control request must name one Issue")
        identifier = match.group(1)
        issue = self.client.get_issue(identifier)
        if issue.get("identifier") != identifier:
            raise GatewayError(f"Issue lookup returned the wrong identifier: {identifier}")
        if request.intent == "status":
            return str(issue.get("status", ""))
        if request.intent == "retry":
            self.client.rerun_issue(identifier)
            return identifier
        assignee_type = issue.get("assignee_type")
        assignee_id = issue.get("assignee_id")
        if assignee_type not in {"agent", "squad"} or not isinstance(assignee_id, str):
            raise GatewayError(f"Issue {identifier} has no routable assignee")
        remainder = ISSUE_PATTERN.sub("", request.user_text, count=1).strip(" ,:：")
        content = f"mention://{assignee_type}/{assignee_id}"
        if remainder:
            content += f"\n\n{remainder}"
        self.client.add_issue_comment(identifier, content)
        return identifier
