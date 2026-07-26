#!/usr/bin/env python3
"""Regression checks for the repository-owned Squad runtime contract."""

import json
import os
from pathlib import Path


ROOT = Path(os.environ.get("CONTRACT_ROOT", Path(__file__).resolve().parents[1])).resolve()


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


def test_pr_sweep_caller_compatibility() -> None:
    company = read("AGENTS.md")
    workspace = read("workspace-context.md")
    orchestrator = read("agents/orchestrator/skill.md")
    sweep = read(".github/scripts/pr-sweep.sh")
    assert "Assign complex or multi-role work to one exact owning Squad" in company
    assert "trivial, single-owner, low-risk" in company
    compatibility_rule = "PR-sweep compatibility exception"
    assert compatibility_rule in company
    assert compatibility_rule in workspace
    assert "Compatibility boundary" in orchestrator
    assert "one dedicated, serialized review issue" in company
    assert "non-author Engineer, Evaluator, and Orchestrator" in company
    assert 'multica issue update "$issue_id" --status in_progress --assignee "$agent"' in sweep
    assert 'multica issue update "$issue_id" --status in_progress --assignee "$CEO_AGENT"' in sweep


def test_fallback_eligibility_contract() -> None:
    company = read("AGENTS.md")
    workspace = read("workspace-context.md")
    template = read("templates/squad-issue.md")
    assert "No fallback identity is live merely because a repository field names one" in company
    fallback_rule = (
        "A fallback is eligible only when it is a separate Orchestrator identity, "
        "deployed and added to every affected Squad, and a fresh topology verify "
        "proves that exact topology."
    )
    for surface in (company, workspace, template):
        assert fallback_rule in surface
    assert "## Owning Squad" in template
    assert "## Correlation ID" in template
    assert "## Result Contract" in template
    deployments = json.loads(read("deployments/agents.json"))
    assert all(item["logical_id"] != "orchestrator-fallback" for item in deployments)
    for manifest in sorted((ROOT / "squads").glob("*/squad.json")):
        squad = json.loads(manifest.read_text(encoding="utf-8"))
        assert "fallback_leader" not in squad, manifest


def test_lost_response_result_idempotency() -> None:
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
    assert "<!-- squad-result: sha256:<correlation-hash> -->" in orchestrator
    assert "multica issue comment list" in orchestrator
    assert "reuse that comment UUID" in orchestrator
    assert "Before the initial write and before every retry" in orchestrator
    assert "More than one exact marker match" in orchestrator


def test_final_result_schema_and_order() -> None:
    orchestrator = read("agents/orchestrator/skill.md")
    assert_in_order(
        orchestrator,
        "1. Post or recover one consolidated result comment on the parent issue",
        "2. Write and verify all five metadata keys",
        "3. Record `multica squad activity`",
        "4. Change the parent status",
    )


def test_specialized_close_order() -> None:
    orchestrator = read("agents/orchestrator/skill.md")
    harness = read("templates/auto-harness.md")
    assert "Deterministic Parent Close Sequence" in harness
    assert "closes the parent (`done`)" not in orchestrator
    assert "closes the parent (`done`)" not in harness
    assert "Set parent status `in_review`" not in harness
    assert "do not change status here" in harness


def test_native_stage_contract() -> None:
    orchestrator = read("agents/orchestrator/skill.md")
    harness = read("templates/auto-harness.md")
    assert "--stage 1 --status todo" in orchestrator
    assert "--stage <N> --status backlog" in orchestrator
    assert "Only `done` and `cancelled` close a native barrier" in orchestrator
    assert "`blocked` keeps the frontier open" in orchestrator
    assert "does not promote later backlog children" in orchestrator
    assert "when ALL `harness:cp` children" not in orchestrator
    assert "--stage <1 for the first runnable frontier" in harness
    assert "--status <todo for Stage 1; backlog for later stages>" in harness
    assert "When the CEO observes (on any re-trigger) that ALL" not in harness


def test_monitoring_and_recovery_contract() -> None:
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
    assert "Record caller and runtime Multica CLI versions" in orchestrator
    assert "fields available and mutually verified on both versions" in orchestrator


def test_recursive_descendant_cancellation() -> None:
    orchestrator = read("agents/orchestrator/skill.md")
    assert "complete descendant issue graph" in orchestrator
    assert "recursively" in orchestrator
    assert "deepest descendants first" in orchestrator
    assert "Re-run descendant discovery" in orchestrator
    assert "relevant children" not in orchestrator
    assert_in_order(
        orchestrator,
        "1. Discover the complete descendant issue graph",
        "2. Enumerate active task IDs",
        "3. Cancel each active task",
        "4. Re-run `multica issue runs`",
        "5. Re-run descendant discovery",
        "6. Only then set every issue in the graph to `cancelled`",
    )


def main() -> None:
    tests = (
        test_mirrored_company_contract,
        test_pr_sweep_caller_compatibility,
        test_fallback_eligibility_contract,
        test_lost_response_result_idempotency,
        test_final_result_schema_and_order,
        test_specialized_close_order,
        test_native_stage_contract,
        test_monitoring_and_recovery_contract,
        test_recursive_descendant_cancellation,
    )
    failed = 0
    for test in tests:
        try:
            test()
        except (AssertionError, FileNotFoundError) as exc:
            failed += 1
            print(f"FAIL: {test.__name__}: {exc}")
        else:
            print(f"PASS: {test.__name__}")
    if failed:
        raise SystemExit(f"FAIL: {failed} Squad runtime contract test(s)")
    print("PASS: Squad runtime contract tests")


if __name__ == "__main__":
    main()
