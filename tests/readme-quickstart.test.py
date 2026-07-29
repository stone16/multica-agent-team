#!/usr/bin/env python3
"""Verify the focused contract test is executable exactly as documented."""

from pathlib import Path
import os
import shlex
import subprocess


ROOT = Path(os.environ.get("CONTRACT_ROOT", Path(__file__).resolve().parents[1])).resolve()
EXPECTED = "python3 tests/squad-runtime-contract.test.py"


def main() -> None:
    for readme in ("README.md", "README.en.md"):
        content = (ROOT / readme).read_text(encoding="utf-8")
        assert EXPECTED in content, f"{readme} must invoke the Python test via python3"

    result = subprocess.run(
        shlex.split(EXPECTED),
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    assert result.returncode == 0, result.stderr or result.stdout
    assert "PASS: Squad runtime contract tests" in result.stdout
    print("PASS: README quick-start contract test executes as documented")


if __name__ == "__main__":
    main()
