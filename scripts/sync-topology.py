#!/usr/bin/env python3
"""Plan, apply, or verify Multica agent deployment and Squad topology."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DEPLOYMENTS = ROOT / "deployments" / "agents.json"
SQUADS_DIR = ROOT / "squads"


class TopologyError(RuntimeError):
    pass


def run(*args: str, input_text: str | None = None) -> str:
    proc = subprocess.run(
        args,
        cwd=ROOT,
        input=input_text,
        text=True,
        capture_output=True,
    )
    if proc.returncode:
        detail = proc.stderr.strip() or proc.stdout.strip() or f"exit {proc.returncode}"
        raise TopologyError(f"{' '.join(args[:3])} failed: {detail}")
    return proc.stdout


def multica_json(*args: str) -> object:
    read_only = "list" in args or (len(args) > 1 and args[1] == "get")
    attempts = 3 if read_only else 1
    for attempt in range(1, attempts + 1):
        try:
            raw = run("multica", *args, "--output", "json")
            break
        except TopologyError:
            if attempt == attempts:
                raise
            print(
                f"read failed (attempt {attempt}/{attempts}); retrying: multica {' '.join(args[:3])}",
                file=sys.stderr,
            )
            time.sleep(1)
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise TopologyError(f"multica {' '.join(args)} returned invalid JSON") from exc


def norm(value: str) -> str:
    return value.strip().casefold()


def same_text(left: str, right: str) -> bool:
    return left.rstrip("\n") == right.rstrip("\n")


def assert_apply_checkout() -> None:
    branch = run("git", "branch", "--show-current").strip()
    if branch != "main":
        raise TopologyError(f"--apply requires branch main; current branch is {branch or 'detached'}")
    if run("git", "status", "--porcelain").strip():
        raise TopologyError("--apply requires a clean working tree")
    run("git", "rev-parse", "--verify", "origin/main")
    if run("git", "rev-parse", "HEAD").strip() != run("git", "rev-parse", "origin/main").strip():
        raise TopologyError("--apply requires HEAD to equal origin/main")


def validate_mirrors() -> None:
    agents = (ROOT / "AGENTS.md").read_bytes()
    claude = (ROOT / "CLAUDE.md").read_bytes()
    if agents != claude:
        raise TopologyError("AGENTS.md and CLAUDE.md must be byte-identical")


def load_desired() -> tuple[list[dict], list[dict]]:
    validate_mirrors()
    deployments = json.loads(DEPLOYMENTS.read_text())
    squads = []
    for manifest in sorted(SQUADS_DIR.glob("*/squad.json")):
        squad = json.loads(manifest.read_text())
        instructions = manifest.with_name("instructions.md")
        if not instructions.is_file():
            raise TopologyError(f"missing {instructions.relative_to(ROOT)}")
        squad["instructions"] = instructions.read_text()
        squad["source"] = str(manifest.parent.relative_to(ROOT))
        squads.append(squad)

    logical_ids = [item["logical_id"] for item in deployments]
    if len(logical_ids) != len(set(logical_ids)):
        raise TopologyError("deployments/agents.json contains duplicate logical_id values")
    squad_names = [norm(item["name"]) for item in squads]
    if len(squad_names) != len(set(squad_names)):
        raise TopologyError("squad manifests contain duplicate names")
    if not squads:
        raise TopologyError("no squad manifests found")

    known = set(logical_ids)
    for squad in squads:
        if "fallback_leader" in squad:
            raise TopologyError(
                f"{squad['source']} fallback_leader is not a synchronized Multica field; "
                "do not advertise an unroutable fallback"
            )
        refs = [squad["leader"], *[member["agent"] for member in squad["members"]]]
        missing = sorted(set(refs) - known)
        if missing:
            raise TopologyError(f"{squad['source']} references unknown agents: {', '.join(missing)}")
    return deployments, squads


def unique_by_name(items: list[dict], kind: str) -> dict[str, dict]:
    grouped: dict[str, list[dict]] = {}
    for item in items:
        grouped.setdefault(norm(item.get("name", "")), []).append(item)
    duplicates = [values[0].get("name", "") for values in grouped.values() if len(values) > 1]
    if duplicates:
        raise TopologyError(f"ambiguous remote {kind} names: {', '.join(duplicates)}")
    return {key: values[0] for key, values in grouped.items()}


def resolve_runtime(runtimes: list[dict], provider: str) -> dict:
    env_name = "SYNC_RUNTIME_" + provider.upper().replace("-", "_")
    target = os.environ.get(env_name, "").strip()
    if target:
        matches = [
            runtime for runtime in runtimes
            if runtime.get("id") == target or norm(runtime.get("name", "")) == norm(target)
        ]
        if len(matches) != 1:
            raise TopologyError(
                f"{env_name} matched {len(matches)} runtimes; use one exact runtime name or id"
            )
        runtime = matches[0]
        if norm(runtime.get("provider", "")) != norm(provider):
            raise TopologyError(f"{env_name} resolves to provider {runtime.get('provider')}, not {provider}")
        if runtime.get("status") != "online":
            raise TopologyError(f"{env_name} resolves to an offline runtime")
        return runtime
    matches = [r for r in runtimes if norm(r.get("provider", "")) == norm(provider) and r.get("status") == "online"]
    if len(matches) != 1:
        raise TopologyError(
            f"expected exactly one online {provider} runtime, found {len(matches)}; no runtime was guessed"
        )
    return matches[0]


def target_name(item: dict) -> str:
    env_name = "SYNC_AGENT_" + item["logical_id"].upper().replace("-", "_")
    return os.environ.get(env_name, "").strip() or item.get("desired_name", item["logical_id"].title())


def resolve_agent(item: dict, agents_by_name: dict[str, dict]) -> dict | None:
    names = [target_name(item)]
    if item.get("desired_name"):
        names.append(item["desired_name"])
    names.extend(item.get("legacy_names", []))
    matches = [agents_by_name[norm(name)] for name in names if norm(name) in agents_by_name]
    unique = {agent["id"]: agent for agent in matches}
    if len(unique) > 1:
        raise TopologyError(f"multiple remote agents match {item['logical_id']}; no identity was guessed")
    return next(iter(unique.values()), None)


def desired_personality(item: dict) -> str:
    path = ROOT / "agents" / item["profession"] / "personality.md"
    if not path.is_file():
        raise TopologyError(f"missing profession personality: {path.relative_to(ROOT)}")
    return path.read_text()


def desired_skill(item: dict) -> Path:
    path = ROOT / "agents" / item["profession"] / "skill.md"
    if not path.is_file():
        raise TopologyError(f"missing profession skill: {path.relative_to(ROOT)}")
    return path


def plan_agents(deployments: list[dict], agents: list[dict], runtimes: list[dict], apply: bool) -> tuple[list[dict], int]:
    by_name = unique_by_name(agents, "agent")
    runtime_by_id = {runtime["id"]: runtime for runtime in runtimes}
    resolved: list[dict] = []
    drift = 0

    for item in deployments:
        desired_runtime = resolve_runtime(runtimes, item["runtime_provider"])
        agent = resolve_agent(item, by_name)
        actions: list[str] = []
        if agent is None:
            if not item.get("create_if_missing", False):
                raise TopologyError(f"agent {item['logical_id']} is missing and is not creatable")
            actions.append("create")
        else:
            current_runtime = runtime_by_id.get(agent.get("runtime_id"), {})
            if agent.get("name") != item.get("desired_name", agent.get("name")):
                actions.append("rename")
            if norm(current_runtime.get("provider", "")) != norm(item["runtime_provider"]):
                actions.append("runtime")
            if (agent.get("model") or "") != item.get("model", ""):
                actions.append("model")

        if actions:
            drift += 1
            print(f"agent\t{item['logical_id']}\t{','.join(actions)}")
            if apply:
                if agent is None:
                    args = [
                        "agent", "create", "--name", item.get("desired_name", item["logical_id"].title()),
                        "--description", f"{item['profession'].title()} agent",
                        "--runtime-id", desired_runtime["id"],
                        "--instructions", desired_personality(item),
                        "--permission-mode", "private",
                    ]
                    if item.get("model", ""):
                        args += ["--model", item["model"]]
                    result = multica_json(*args)
                    if not isinstance(result, dict) or not result.get("id"):
                        raise TopologyError(f"create agent {item['logical_id']} returned no id")
                    agent = result
                else:
                    args = ["agent", "update", agent["id"]]
                    if "rename" in actions:
                        args += ["--name", item["desired_name"]]
                    if "runtime" in actions:
                        args += ["--runtime-id", desired_runtime["id"]]
                    if "model" in actions:
                        args += ["--model", item.get("model", "")]
                    agent = multica_json(*args)
        else:
            print(f"agent\t{item['logical_id']}\tup-to-date")

        if agent is not None:
            resolved.append({**item, "remote": agent})

    return resolved, drift


def apply_missing_and_renamed_agents(
    deployments: list[dict], agents: list[dict], runtimes: list[dict]
) -> int:
    by_name = unique_by_name(agents, "agent")
    changes = 0
    for item in deployments:
        desired_runtime = resolve_runtime(runtimes, item["runtime_provider"])
        agent = resolve_agent(item, by_name)
        if agent is None:
            if not item.get("create_if_missing", False):
                continue
            args = [
                "agent", "create", "--name", item.get("desired_name", item["logical_id"].title()),
                "--description", f"{item['profession'].title()} agent",
                "--runtime-id", desired_runtime["id"],
                "--instructions", desired_personality(item),
                "--permission-mode", "private",
            ]
            if item.get("model", ""):
                args += ["--model", item["model"]]
            result = multica_json(*args)
            if not isinstance(result, dict) or not result.get("id"):
                raise TopologyError(f"create agent {item['logical_id']} returned no id")
            changes += 1
        elif "desired_name" in item and agent.get("name") != item["desired_name"]:
            multica_json("agent", "update", agent["id"], "--name", item["desired_name"])
            changes += 1
    return changes


def apply_runtime_and_model_agents(
    deployments: list[dict], agents: list[dict], runtimes: list[dict]
) -> int:
    by_name = unique_by_name(agents, "agent")
    runtime_by_id = {runtime["id"]: runtime for runtime in runtimes}
    changes = 0
    for item in deployments:
        desired_runtime = resolve_runtime(runtimes, item["runtime_provider"])
        agent = resolve_agent(item, by_name)
        if agent is None:
            raise TopologyError(f"agent {item['logical_id']} is still missing after create phase")
        current_runtime = runtime_by_id.get(agent.get("runtime_id"), {})
        args = ["agent", "update", agent["id"]]
        changed = False
        if norm(current_runtime.get("provider", "")) != norm(item["runtime_provider"]):
            args += ["--runtime-id", desired_runtime["id"]]
            changed = True
        if (agent.get("model") or "") != item.get("model", ""):
            args += ["--model", item.get("model", "")]
            changed = True
        if changed:
            multica_json(*args)
            changes += 1
    return changes


def attach_missing_profession_skills(deployed_agents: list[dict]) -> int:
    skills = multica_json("skill", "list")
    if not isinstance(skills, list):
        raise TopologyError("Multica skill list response must be a JSON array")
    skills_by_name = unique_by_name(skills, "skill")
    profession_skill_ids: dict[str, str] = {}

    for item in deployed_agents:
        profession = item["profession"]
        if profession in profession_skill_ids:
            continue
        skill_path = desired_skill(item)
        skill_name = f"{profession.title()} Skill"
        skill = skills_by_name.get(norm(skill_name))
        if skill is None:
            result = multica_json(
                "skill", "create", "--name", skill_name,
                "--description", f"Operational rules for the {profession.title()} agent. Self-contained.",
                "--content-file", str(skill_path.relative_to(ROOT)),
            )
            if not isinstance(result, dict) or not result.get("id"):
                raise TopologyError(f"create skill {skill_name} returned no id")
            skill = result
        profession_skill_ids[profession] = skill["id"]

    changes = 0
    for item in deployed_agents:
        agent = item["remote"]
        skill_id = profession_skill_ids[item["profession"]]
        attached = multica_json("agent", "skills", "list", agent["id"])
        if not isinstance(attached, list):
            raise TopologyError(f"skill list for {item['logical_id']} is not a JSON array")
        if not any(skill.get("id") == skill_id and skill.get("enabled", True) for skill in attached):
            multica_json("agent", "skills", "add", agent["id"], "--skill-ids", skill_id)
            print(f"attachment\t{item['logical_id']}\tadd")
            changes += 1
    return changes


def plan_profession_skill_names(deployments: list[dict], skills: list[dict], apply: bool) -> int:
    by_name = unique_by_name(skills, "skill")
    drift = 0
    seen: set[str] = set()
    for item in deployments:
        profession = item["profession"]
        if profession in seen:
            continue
        seen.add(profession)
        desired_name = f"{profession.title()} Skill"
        if norm(desired_name) in by_name:
            continue
        legacy = [by_name[norm(name)] for name in item.get("legacy_skill_names", []) if norm(name) in by_name]
        unique = {skill["id"]: skill for skill in legacy}
        if len(unique) > 1:
            raise TopologyError(f"multiple legacy skills match {profession}; no skill was guessed")
        if len(unique) == 1:
            drift += 1
            skill = next(iter(unique.values()))
            print(f"skill\t{profession}\trename {skill['name']} -> {desired_name}")
            if apply:
                multica_json(
                    "skill", "update", skill["id"], "--name", desired_name,
                    "--content-file", str(desired_skill(item).relative_to(ROOT)),
                )
    return drift


def plan_squads(squads: list[dict], deployed_agents: list[dict], remote_squads: list[dict], apply: bool) -> int:
    agents = {item["logical_id"]: item["remote"] for item in deployed_agents}
    by_name = unique_by_name(remote_squads, "squad")
    drift = 0

    for desired in squads:
        if desired["leader"] not in agents:
            raise TopologyError(f"cannot resolve leader for {desired['name']}")
        leader = agents[desired["leader"]]
        squad = by_name.get(norm(desired["name"]))
        actions: list[str] = []
        if squad is None:
            actions.append("create")
        else:
            if squad.get("description", "") != desired["description"]:
                actions.append("description")
            if squad.get("leader_id") != leader["id"]:
                actions.append("leader")
            if not same_text(squad.get("instructions", ""), desired["instructions"]):
                actions.append("instructions")

        if actions:
            drift += 1
            print(f"squad\t{desired['name']}\t{','.join(actions)}")
            if apply:
                if squad is None:
                    squad = multica_json(
                        "squad", "create", "--name", desired["name"],
                        "--description", desired["description"], "--leader", leader["id"]
                    )
                squad = multica_json(
                    "squad", "update", squad["id"],
                    "--description", desired["description"],
                    "--instructions", desired["instructions"],
                    "--leader", leader["id"],
                )
        else:
            print(f"squad\t{desired['name']}\tup-to-date")

        if squad is None:
            continue

        remote_members = multica_json("squad", "member", "list", squad["id"])
        if not isinstance(remote_members, list):
            raise TopologyError(f"member list for {desired['name']} is not a JSON list")
        current = {(m["member_type"], m["member_id"]): m for m in remote_members}
        expected = [(leader, "leader")]
        for member in desired["members"]:
            if member["agent"] not in agents:
                raise TopologyError(f"cannot resolve {member['agent']} for {desired['name']}")
            expected.append((agents[member["agent"]], member["role"]))

        expected_keys = {("agent", agent["id"]) for agent, _ in expected}
        extra = [m for key, m in current.items() if key not in expected_keys]
        if extra:
            names_by_id = {item["remote"]["id"]: item["remote"]["name"] for item in deployed_agents}
            extras = ", ".join(names_by_id.get(m["member_id"], "unmanaged member") for m in extra)
            raise TopologyError(
                f"{desired['name']} has extra members ({extras}); automatic removal is intentionally forbidden"
            )

        for agent, role in expected:
            key = ("agent", agent["id"])
            member = current.get(key)
            if member is None:
                drift += 1
                print(f"member\t{desired['name']}/{agent['name']}\tadd")
                if apply:
                    multica_json(
                        "squad", "member", "add", squad["id"],
                        "--member-id", agent["id"], "--type", "agent", "--role", role,
                    )
            elif member.get("role", "") != role:
                drift += 1
                print(f"member\t{desired['name']}/{agent['name']}\trole")
                if apply:
                    multica_json(
                        "squad", "member", "set-role", squad["id"],
                        "--member-id", agent["id"], "--member-type", "agent", "--role", role,
                    )
            else:
                print(f"member\t{desired['name']}/{agent['name']}\tup-to-date")
    return drift


def execute(mode: str, allow_dirty_apply: bool = False) -> int:
    deployments, squads = load_desired()
    if mode == "apply" and not allow_dirty_apply:
        assert_apply_checkout()

    agents = multica_json("agent", "list")
    runtimes = multica_json("runtime", "list")
    skills = multica_json("skill", "list")
    remote_squads = multica_json("squad", "list")
    if not isinstance(agents, list) or not isinstance(runtimes, list) or not isinstance(skills, list) or not isinstance(remote_squads, list):
        raise TopologyError("Multica list responses must be JSON arrays")

    skill_drift = plan_profession_skill_names(deployments, skills, mode == "apply")
    deployed, agent_drift = plan_agents(deployments, agents, runtimes, False)
    if mode == "apply" and agent_drift:
        apply_missing_and_renamed_agents(deployments, agents, runtimes)
        agents = multica_json("agent", "list")
        apply_runtime_and_model_agents(deployments, agents, runtimes)
        agents = multica_json("agent", "list")
        deployed, _ = plan_agents(deployments, agents, runtimes, False)
        attach_missing_profession_skills(deployed)
    squad_drift = plan_squads(squads, deployed, remote_squads, mode == "apply")
    drift = skill_drift + agent_drift + squad_drift

    if mode == "verify" and drift:
        raise TopologyError(f"{drift} topology drift item(s) remain")
    print(f"summary\tmode={mode}\tdrift={drift}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--apply", action="store_true", help="write the planned non-destructive changes")
    group.add_argument("--verify", action="store_true", help="fail if deployed topology differs")
    parser.add_argument("--allow-dirty-apply", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    mode = "apply" if args.apply else "verify" if args.verify else "plan"
    try:
        return execute(mode, args.allow_dirty_apply)
    except (OSError, KeyError, ValueError, TopologyError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
