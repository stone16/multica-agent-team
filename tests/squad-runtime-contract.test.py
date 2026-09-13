#!/usr/bin/env python3
"""Regression checks for the repository-owned Squad runtime contract."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap


ROOT = Path(os.environ.get("CONTRACT_ROOT", Path(__file__).resolve().parents[1])).resolve()


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def assert_in_order(text: str, *needles: str) -> None:
    offset = 0
    for needle in needles:
        position = text.find(needle, offset)
        assert position >= 0, f"missing or out of order: {needle}"
        offset = position + len(needle)


def checkpoint_plan_from_template() -> list[dict[str, object]]:
    template = read("templates/auto-harness.md")
    marker = "[auto-harness: checkpoint-plan]"
    assert marker in template, "checkpoint plan must contain a fenced JSON array"
    plan_section = template.split(marker, 1)[1]
    assert "```json\n" in plan_section, "checkpoint plan must contain a fenced JSON array"
    payload = plan_section.split("```json\n", 1)[1].split("\n   ```", 1)[0]
    payload = textwrap.dedent(payload)
    plan = json.loads(payload)
    assert isinstance(plan, list), "checkpoint plan payload must be an array"
    return plan


def run_checkpoint_plan_validator(plan: object) -> subprocess.CompletedProcess[str]:
    with tempfile.TemporaryDirectory() as temp_dir:
        plan_path = Path(temp_dir) / "checkpoint-plan.json"
        plan_path.write_text(json.dumps(plan), encoding="utf-8")
        return subprocess.run(
            [
                "python3",
                str(ROOT / "agents/orchestrator/files/scripts/validate-checkpoint-plan.py"),
                str(plan_path),
            ],
            cwd=ROOT,
            text=True,
            capture_output=True,
        )


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


def test_pm_split_uses_exact_squad_contract() -> None:
    pm = read("agents/pm/skill.md")
    assert "templates/squad-issue.md" in pm
    assert "--assignee-id <owning-squad-uuid>" in pm
    assert "## Owning Squad" in pm
    assert "## Correlation ID" in pm
    assert "## Result Contract" in pm
    assert "Leave `assignee` empty" not in pm


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
    assert (
        "multica issue comment list <parent-issue-id> --full --output json"
        in orchestrator
    )
    assert "--thread <trigger-comment-id>" not in orchestrator
    assert "different top-level trigger" in orchestrator
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
    assert (
        "--stage <1 for the first runnable frontier" in harness
        or "--stage <validated stage>" in harness
    )
    assert (
        "--status <todo for Stage 1; backlog for later stages>" in harness
        or "--status <validated status>" in harness
    )
    assert "When the CEO observes (on any re-trigger) that ALL" not in harness


def test_checkpoint_plan_graph_contract() -> None:
    orchestrator = read("agents/orchestrator/skill.md")
    plan = checkpoint_plan_from_template()
    result = run_checkpoint_plan_validator(plan)
    assert result.returncode == 0, result.stderr or result.stdout
    normalized = json.loads(result.stdout)
    assert normalized == {
        "children": [
            {
                "create_args": ["--stage", "1", "--status", "todo"],
                "depends_on": [],
                "id": "cp-01",
            },
            {
                "create_args": ["--stage", "2", "--status", "backlog"],
                "depends_on": ["cp-01"],
                "id": "cp-02",
            },
        ]
    }
    assert "scripts/validate-checkpoint-plan.py" in orchestrator
    assert "Never substitute a same-named script from the target repository" in orchestrator
    assert "before creating any child" in orchestrator
    assert "--stage <validated stage> --status <validated status>" in orchestrator
    assert "Depends on: <comma-separated IDs | none>" in orchestrator
    assert "templates/squad-issue.md" in orchestrator
    assert "--assignee-id <exact owning Squad UUID>" in orchestrator
    assert "--assignee-id <Engineer instance UUID>" not in orchestrator

    malformed_cases = (
        ("zero entries", [], "at least one checkpoint"),
        ("missing stage", [{**plan[0], "stage": None}], "stage must be a positive integer"),
        (
            "missing dependency field",
            [{key: value for key, value in plan[0].items() if key != "depends_on"}],
            "missing fields: depends_on",
        ),
        (
            "unknown dependency",
            [plan[0], {**plan[1], "depends_on": ["cp-99"]}],
            "unknown checkpoint: cp-99",
        ),
        (
            "self dependency",
            [{**plan[0], "depends_on": ["cp-01"]}, plan[1]],
            "checkpoint cannot depend on itself",
        ),
        (
            "same-stage dependency",
            [plan[0], {**plan[1], "stage": 1, "depends_on": ["cp-01"]}],
            "Stage 1 depends_on must be empty",
        ),
        (
            "missing later dependency",
            [plan[0], {**plan[1], "depends_on": []}],
            "later-stage checkpoint requires depends_on",
        ),
        (
            "skipped dependency stage",
            [plan[0], {**plan[1], "stage": 3}],
            "stage must be one greater than its latest dependency stage",
        ),
    )
    for name, malformed, expected_error in malformed_cases:
        rejected = run_checkpoint_plan_validator(malformed)
        assert rejected.returncode != 0, f"{name} graph was accepted"
        assert expected_error in rejected.stderr, (name, rejected.stderr)
    print(
        "PASS: checkpoint graph cp-01 --stage 1 --status todo; "
        "cp-02 depends_on=cp-01 --stage 2 --status backlog"
    )
    print("PASS: rejected malformed checkpoint graphs: " + ", ".join(case[0] for case in malformed_cases))


def test_auto_harness_uses_squad_ownership() -> None:
    orchestrator = read("agents/orchestrator/skill.md")
    harness = read("templates/auto-harness.md")
    for surface in (orchestrator, harness):
        assert "templates/squad-issue.md" in surface
        assert "--assignee-id <exact owning Squad UUID>" in surface
        assert "--assignee-id <Engineer instance UUID" not in surface
    assert "assigned to the parent's exact owning Squad" in orchestrator
    assert "assigned directly to an Engineer" not in harness


def test_dual_evaluator_requires_two_distinct_verdicts() -> None:
    orchestrator = read("agents/orchestrator/skill.md")
    assert "verification: dual_evaluator" in orchestrator
    assert "two distinct Evaluator author UUIDs" in orchestrator
    assert "one verdict exists" in orchestrator
    assert "both independent verdicts exist" in orchestrator
    assert "both verdicts are `PASS`" in orchestrator
    assert "either verdict is `FAIL`" in orchestrator
    assert "do not mark the step done" in orchestrator


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
        test_pm_split_uses_exact_squad_contract,
        test_fallback_eligibility_contract,
        test_lost_response_result_idempotency,
        test_final_result_schema_and_order,
        test_specialized_close_order,
        test_native_stage_contract,
        test_checkpoint_plan_graph_contract,
        test_auto_harness_uses_squad_ownership,
        test_dual_evaluator_requires_two_distinct_verdicts,
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
