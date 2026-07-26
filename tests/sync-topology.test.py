#!/usr/bin/env python3
"""Intent tests for the persistent Squad topology reconciler."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def make_fixture(state: str) -> Path:
    tmp = Path(tempfile.mkdtemp())
    repo = tmp / "repo"
    for relative in ["scripts/sync-topology.py", "AGENTS.md", "CLAUDE.md"]:
        source = ROOT / relative
        target = repo / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(source, target)

    write(repo / "AGENTS.md", "same rules\n")
    write(repo / "CLAUDE.md", "same rules\n")
    write(repo / "agents/orchestrator/personality.md", "orchestrator personality\n")
    write(repo / "agents/orchestrator/skill.md", "orchestrator skill\n")
    write(repo / "agents/evaluator/personality.md", "evaluator personality\n")
    write(repo / "agents/evaluator/skill.md", "evaluator skill\n")
    write(
        repo / "deployments/agents.json",
        json.dumps(
            [
                {
                    "logical_id": "orchestrator",
                    "profession": "orchestrator",
                    "runtime_provider": "claude",
                    "model": "claude-opus-5",
                },
                {
                    "logical_id": "evaluator-a",
                    "desired_name": "Evaluator-A",
                    "profession": "evaluator",
                    "runtime_provider": "grok",
                    "model": "",
                    "create_if_missing": True,
                },
            ]
        ),
    )
    write(
        repo / "squads/discovery/squad.json",
        json.dumps(
            {
                "name": "Discovery",
                "description": "Discover",
                "leader": "orchestrator",
                "members": [{"agent": "evaluator-a", "role": "Optional evaluator"}],
            }
        ),
    )
    write(repo / "squads/discovery/instructions.md", "Discovery instructions\n")
    write(tmp / "state.json", json.dumps({"scenario": state, "agents": [], "squads": [], "calls": []}))

    stub = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path

state_path = Path(os.environ["TOPOLOGY_TEST_STATE"])
state = json.loads(state_path.read_text())
args = sys.argv[1:]
state["calls"].append(args)

def save():
    state_path.write_text(json.dumps(state))

if args[:2] == ["agent", "list"]:
    agents = state["agents"] or [{"id":"a-lead","name":"Existing Orchestrator","runtime_id":"r-claude","model":"claude-opus-5"}]
    print(json.dumps(agents))
elif args[:2] == ["runtime", "list"]:
    print(json.dumps([
        {"id":"r-claude","name":"Claude","provider":"claude","status":"online"},
        {"id":"r-grok","name":"Grok","provider":"grok","status":"online"}
    ]))
elif args[:2] == ["skill", "list"]:
    print(json.dumps([
        {"id":"sk-orchestrator","name":"Orchestrator Skill"},
        {"id":"sk-evaluator","name":"Evaluator Skill"}
    ]))
elif args[:2] == ["skill", "create"]:
    print(json.dumps({"id":"sk-created","name":args[args.index("--name") + 1]}))
elif args[:2] == ["squad", "list"]:
    print(json.dumps(state["squads"]))
elif args[:2] == ["agent", "create"]:
    name = args[args.index("--name") + 1]
    runtime = args[args.index("--runtime-id") + 1]
    created = {"id":"a-eval","name":name,"runtime_id":runtime,"model":""}
    state["agents"] = [{"id":"a-lead","name":"Existing Orchestrator","runtime_id":"r-claude","model":"claude-opus-5"}, created]
    save(); print(json.dumps(created))
elif args[:2] == ["agent", "update"]:
    updated = None
    for agent in state["agents"]:
        if agent["id"] != args[2]:
            continue
        if "--name" in args:
            agent["name"] = args[args.index("--name") + 1]
        if "--runtime-id" in args:
            agent["runtime_id"] = args[args.index("--runtime-id") + 1]
        if "--model" in args:
            agent["model"] = args[args.index("--model") + 1]
        updated = agent
    if updated is None:
        updated = {"id":args[2]}
    save(); print(json.dumps(updated))
elif args[:3] == ["agent", "skills", "list"]:
    print(json.dumps([]))
elif args[:3] == ["agent", "skills", "add"]:
    print(json.dumps({"ok": True}))
elif args[:2] == ["squad", "create"]:
    created = {"id":"s-discovery","name":"Discovery","description":"Discover","leader_id":"a-lead","instructions":""}
    state["squads"] = [created]
    save(); print(json.dumps(created))
elif args[:2] == ["squad", "update"]:
    instructions = args[args.index("--instructions") + 1]
    updated = {"id":"s-discovery","name":"Discovery","description":"Discover","leader_id":"a-lead","instructions":instructions}
    state["squads"] = [updated]
    save(); print(json.dumps(updated))
elif args[:3] == ["squad", "member", "list"]:
    if state["scenario"] == "extra-member":
        print(json.dumps([{"member_type":"agent","member_id":"a-extra","role":"legacy"}]))
    else:
        print(json.dumps([
            {"member_type":"agent","member_id":"a-lead","role":"leader"},
            {"member_type":"agent","member_id":"a-eval","role":"Optional evaluator"}
        ] if state["scenario"] == "matched" else []))
elif args[:3] in (["squad", "member", "add"], ["squad", "member", "set-role"]):
    print(json.dumps({"ok": True}))
else:
    print("unexpected: " + " ".join(args), file=sys.stderr); save(); sys.exit(2)
save()
'''
    write(tmp / "bin/multica", stub)
    os.chmod(tmp / "bin/multica", 0o755)
    return tmp


def run_fixture(tmp: Path, *args: str) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["PATH"] = str(tmp / "bin") + os.pathsep + env["PATH"]
    env["TOPOLOGY_TEST_STATE"] = str(tmp / "state.json")
    env["SYNC_AGENT_ORCHESTRATOR"] = "Existing Orchestrator"
    env["SYNC_AGENT_EVALUATOR_A"] = "Legacy Evaluator"
    return subprocess.run(
        [str(tmp / "repo/scripts/sync-topology.py"), *args],
        cwd=tmp / "repo",
        env=env,
        text=True,
        capture_output=True,
    )


def test_plan_is_read_only() -> None:
    tmp = make_fixture("drift")
    result = run_fixture(tmp)
    assert result.returncode == 0, result.stderr
    state = json.loads((tmp / "state.json").read_text())
    assert not any(call[:2] == ["agent", "create"] for call in state["calls"])
    assert not any(call[:2] == ["squad", "create"] for call in state["calls"])
    assert "agent\tevaluator-a\tcreate" in result.stdout
    assert "squad\tDiscovery\tcreate" in result.stdout


def test_apply_creates_missing_instance_and_squad() -> None:
    tmp = make_fixture("drift")
    result = run_fixture(tmp, "--apply", "--allow-dirty-apply")
    assert result.returncode == 0, result.stderr
    state = json.loads((tmp / "state.json").read_text())
    assert any(call[:2] == ["agent", "create"] for call in state["calls"])
    assert any(call[:2] == ["squad", "create"] for call in state["calls"])
    assert any(call[:3] == ["squad", "member", "add"] for call in state["calls"])


def test_apply_upgrades_legacy_claude_model() -> None:
    tmp = make_fixture("matched")
    write(
        tmp / "state.json",
        json.dumps(
            {
                "scenario": "matched",
                "agents": [
                    {"id":"a-lead","name":"Existing Orchestrator","runtime_id":"r-claude","model":"claude-opus-4-8"},
                    {"id":"a-eval","name":"Legacy Evaluator","runtime_id":"r-grok","model":""},
                ],
                "squads": [{"id":"s-discovery","name":"Discovery","description":"Discover","leader_id":"a-lead","instructions":"Discovery instructions\n"}],
                "calls": [],
            }
        ),
    )
    result = run_fixture(tmp, "--apply", "--allow-dirty-apply")
    assert result.returncode == 0, result.stderr
    state = json.loads((tmp / "state.json").read_text())
    orchestrator = next(agent for agent in state["agents"] if agent["id"] == "a-lead")
    assert orchestrator["model"] == "claude-opus-5"
    assert any(
        call[:3] == ["agent", "update", "a-lead"]
        and call[call.index("--model") + 1] == "claude-opus-5"
        for call in state["calls"]
        if "--model" in call
    )


def test_apply_keeps_identity_across_rename_and_runtime_change() -> None:
    tmp = make_fixture("matched")
    write(
        tmp / "state.json",
        json.dumps(
            {
                "scenario": "matched",
                "agents": [
                    {"id":"a-lead","name":"Existing Orchestrator","runtime_id":"r-claude","model":"claude-opus-5"},
                    {"id":"a-eval","name":"Legacy Evaluator","runtime_id":"r-claude","model":"claude-opus-4-8"},
                ],
                "squads": [],
                "calls": [],
            }
        ),
    )
    result = run_fixture(tmp, "--apply", "--allow-dirty-apply")
    assert result.returncode == 0, result.stderr
    state = json.loads((tmp / "state.json").read_text())
    evaluator = next(agent for agent in state["agents"] if agent["id"] == "a-eval")
    assert evaluator["name"] == "Evaluator-A"
    assert evaluator["runtime_id"] == "r-grok"
    assert evaluator["model"] == ""


def test_verify_rejects_drift_and_accepts_convergence() -> None:
    tmp = make_fixture("drift")
    result = run_fixture(tmp, "--verify")
    assert result.returncode != 0
    assert "topology drift item" in result.stderr

    tmp = make_fixture("matched")
    write(
        tmp / "state.json",
        json.dumps(
            {
                "scenario": "matched",
                "agents": [
                    {"id":"a-lead","name":"Existing Orchestrator","runtime_id":"r-claude","model":"claude-opus-5"},
                    {"id":"a-eval","name":"Evaluator-A","runtime_id":"r-grok","model":""},
                ],
                "squads": [{"id":"s-discovery","name":"Discovery","description":"Discover","leader_id":"a-lead","instructions":"Discovery instructions\n"}],
                "calls": [],
            }
        ),
    )
    result = run_fixture(tmp, "--verify")
    assert result.returncode == 0, result.stderr
    assert "drift=0" in result.stdout


def test_extra_members_fail_closed() -> None:
    tmp = make_fixture("extra-member")
    write(
        tmp / "state.json",
        json.dumps(
            {
                "scenario": "extra-member",
                "agents": [
                    {"id":"a-lead","name":"Existing Orchestrator","runtime_id":"r-claude","model":"claude-opus-5"},
                    {"id":"a-eval","name":"Evaluator-A","runtime_id":"r-grok","model":""},
                ],
                "squads": [{"id":"s-discovery","name":"Discovery","description":"Discover","leader_id":"a-lead","instructions":"Discovery instructions\n"}],
                "calls": [],
            }
        ),
    )
    result = run_fixture(tmp, "--verify")
    assert result.returncode != 0
    assert "automatic removal is intentionally forbidden" in result.stderr


def test_unroutable_fallback_field_fails_closed() -> None:
    tmp = make_fixture("drift")
    manifest = tmp / "repo/squads/discovery/squad.json"
    squad = json.loads(manifest.read_text())
    squad["fallback_leader"] = "evaluator-a"
    manifest.write_text(json.dumps(squad))
    result = run_fixture(tmp)
    assert result.returncode != 0
    assert "fallback_leader is not a synchronized Multica field" in result.stderr


def main() -> None:
    test_plan_is_read_only()
    test_apply_creates_missing_instance_and_squad()
    test_apply_upgrades_legacy_claude_model()
    test_apply_keeps_identity_across_rename_and_runtime_change()
    test_verify_rejects_drift_and_accepts_convergence()
    test_extra_members_fail_closed()
    test_unroutable_fallback_field_fails_closed()
    print("PASS: topology desired-state tests")


if __name__ == "__main__":
    main()
