#!/usr/bin/env python3
"""Regression checks for the repository-owned Squad runtime contract."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def assert_in_order(text: str, *needles: str) -> None:
    offset = 0
    for needle in needles:
        position = text.find(needle, offset)
        assert position >= 0, f"missing or out of order: {needle}"
        offset = position + len(needle)


def test_mirrored_company_contract() -> None:
    assert read("AGENTS.md") == read("CLAUDE.md")


def test_squad_routing_and_fallback_contract() -> None:
    company = read("AGENTS.md")
    template = read("templates/squad-issue.md")
    assert "Assign complex or multi-role work to one exact owning Squad" in company
    assert "trivial, single-owner, low-risk" in company
    assert "No fallback identity is live merely because a repository field names one" in company
    assert "## Owning Squad" in template
    assert "## Correlation ID" in template
    assert "## Result Contract" in template
    deployments = json.loads(read("deployments/agents.json"))
    assert all(item["logical_id"] != "orchestrator-fallback" for item in deployments)
    for manifest in sorted((ROOT / "squads").glob("*/squad.json")):
        squad = json.loads(manifest.read_text(encoding="utf-8"))
        assert "fallback_leader" not in squad, manifest


def test_final_result_schema_and_order() -> None:
    orchestrator = read("agents/orchestrator/skill.md")
    required_keys = (
        "squad_verdict",
        "squad_result_comment_id",
        "squad_next_owner",
        "squad_evidence_complete",
        "correlation_id",
    )
    for key in required_keys:
        assert key in orchestrator
    assert "delivered | inconclusive | blocked | escalated" in orchestrator
    assert "--parent <trigger-comment-id>" in orchestrator
    assert_in_order(
        orchestrator,
        "1. Post one consolidated result comment on the parent issue",
        "2. Write and verify all five metadata keys",
        "3. Record `multica squad activity`",
        "4. Change the parent status",
    )


def test_native_stage_contract() -> None:
    orchestrator = read("agents/orchestrator/skill.md")
    assert "--stage 1 --status todo" in orchestrator
    assert "--stage <N> --status backlog" in orchestrator
    assert "Only `done` and `cancelled` close a native barrier" in orchestrator
    assert "`blocked` keeps the frontier open" in orchestrator
    assert "does not promote later backlog children" in orchestrator
    assert "when ALL `harness:cp` children" not in orchestrator
    harness = read("templates/auto-harness.md")
    assert "--stage <1 for the first runnable frontier" in harness
    assert "--status <todo for Stage 1; backlog for later stages>" in harness
    assert "When the CEO observes (on any re-trigger) that ALL" not in harness


def test_monitoring_recovery_and_cancellation_contract() -> None:
    orchestrator = read("agents/orchestrator/skill.md")
    for command in (
        "multica issue get",
        "multica issue children",
        "multica issue runs",
        "multica issue run-messages",
        "multica issue metadata list",
        "multica issue cancel-task",
    ):
        assert command in orchestrator
    assert "caller-configured freshness window" in orchestrator
    assert "re-dispatch only the missing artifact or verification lane" in orchestrator
    assert_in_order(
        orchestrator,
        "1. Enumerate active task IDs",
        "2. Cancel each active task",
        "3. Re-run `multica issue runs`",
        "4. Only then set the parent and relevant children to `cancelled`",
    )


def main() -> None:
    test_mirrored_company_contract()
    test_squad_routing_and_fallback_contract()
    test_final_result_schema_and_order()
    test_native_stage_contract()
    test_monitoring_recovery_and_cancellation_contract()
    print("PASS: Squad runtime contract tests")


if __name__ == "__main__":
    main()
