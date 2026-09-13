#!/usr/bin/env python3
"""Validate and normalize an auto-harness checkpoint dependency graph."""

import json
from pathlib import Path
import re
import sys
from typing import NoReturn


CHECKPOINT_ID = re.compile(r"cp-[0-9]+")
REQUIRED_FIELDS = {"id", "title", "stage", "depends_on", "body", "suggested_dod"}
REQUIRED_DOD_FIELDS = {"outcome", "evidence", "verification", "max_rounds"}
VERIFICATION_LEVELS = {"self", "evaluator", "dual_evaluator", "human"}


def reject(message: str) -> NoReturn:
    raise ValueError(message)


def require_non_empty_string(value: object, field: str, checkpoint_id: str) -> str:
    if not isinstance(value, str) or not value.strip():
        reject(f"{checkpoint_id}: {field} must be a non-empty string")
    return value


def validate_entry(entry: object, index: int) -> dict[str, object]:
    if not isinstance(entry, dict):
        reject(f"entry {index}: checkpoint must be an object")
    missing = sorted(REQUIRED_FIELDS - entry.keys())
    if missing:
        reject(f"entry {index}: missing fields: {', '.join(missing)}")

    checkpoint_id = require_non_empty_string(entry["id"], "id", f"entry {index}")
    if CHECKPOINT_ID.fullmatch(checkpoint_id) is None:
        reject(f"entry {index}: id must match cp-<number>")
    require_non_empty_string(entry["title"], "title", checkpoint_id)
    require_non_empty_string(entry["body"], "body", checkpoint_id)

    stage = entry["stage"]
    if isinstance(stage, bool) or not isinstance(stage, int) or stage < 1:
        reject(f"{checkpoint_id}: stage must be a positive integer")

    depends_on = entry["depends_on"]
    if not isinstance(depends_on, list) or any(not isinstance(item, str) for item in depends_on):
        reject(f"{checkpoint_id}: depends_on must be an array of checkpoint IDs")
    if len(depends_on) != len(set(depends_on)):
        reject(f"{checkpoint_id}: depends_on must not contain duplicates")

    dod = entry["suggested_dod"]
    if not isinstance(dod, dict):
        reject(f"{checkpoint_id}: suggested_dod must be an object")
    missing_dod = sorted(REQUIRED_DOD_FIELDS - dod.keys())
    if missing_dod:
        reject(f"{checkpoint_id}: suggested_dod missing fields: {', '.join(missing_dod)}")
    require_non_empty_string(dod["outcome"], "suggested_dod.outcome", checkpoint_id)
    require_non_empty_string(dod["evidence"], "suggested_dod.evidence", checkpoint_id)
    if dod["verification"] not in VERIFICATION_LEVELS:
        reject(f"{checkpoint_id}: suggested_dod.verification is invalid")
    max_rounds = dod["max_rounds"]
    if isinstance(max_rounds, bool) or not isinstance(max_rounds, int) or max_rounds < 1:
        reject(f"{checkpoint_id}: suggested_dod.max_rounds must be a positive integer")
    return entry


def validate_plan(payload: object) -> dict[str, list[dict[str, object]]]:
    if not isinstance(payload, list) or not payload:
        reject("checkpoint plan must contain at least one checkpoint")

    entries = [validate_entry(entry, index) for index, entry in enumerate(payload, start=1)]
    by_id: dict[str, dict[str, object]] = {}
    for entry in entries:
        checkpoint_id = str(entry["id"])
        if checkpoint_id in by_id:
            reject(f"duplicate checkpoint id: {checkpoint_id}")
        by_id[checkpoint_id] = entry

    children: list[dict[str, object]] = []
    for entry in entries:
        checkpoint_id = str(entry["id"])
        stage = int(entry["stage"])
        depends_on = list(entry["depends_on"])
        if checkpoint_id in depends_on:
            reject(f"{checkpoint_id}: checkpoint cannot depend on itself")
        if stage == 1 and depends_on:
            reject(f"{checkpoint_id}: Stage 1 depends_on must be empty")
        if stage > 1 and not depends_on:
            reject(f"{checkpoint_id}: later-stage checkpoint requires depends_on")

        dependency_stages: list[int] = []
        for dependency_id in depends_on:
            if dependency_id not in by_id:
                reject(f"{checkpoint_id}: unknown checkpoint: {dependency_id}")
            dependency_stage = int(by_id[dependency_id]["stage"])
            if dependency_stage >= stage:
                reject(f"{checkpoint_id}: dependency {dependency_id} must be in an earlier stage")
            dependency_stages.append(dependency_stage)

        if dependency_stages and stage != max(dependency_stages) + 1:
            reject(f"{checkpoint_id}: stage must be one greater than its latest dependency stage")

        children.append(
            {
                "create_args": [
                    "--stage",
                    str(stage),
                    "--status",
                    "todo" if stage == 1 else "backlog",
                ],
                "depends_on": depends_on,
                "id": checkpoint_id,
            }
        )
    return {"children": children}


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: validate-checkpoint-plan.py <checkpoint-plan.json>")
    try:
        payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
        normalized = validate_plan(payload)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"invalid checkpoint plan: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
    print(json.dumps(normalized, sort_keys=True))


if __name__ == "__main__":
    main()
