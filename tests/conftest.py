"""Shared fixtures for the test suites in this directory."""
from pathlib import Path
import subprocess

import pytest

REPO = Path(__file__).resolve().parent.parent


@pytest.fixture(scope="session")
def repo():
    return REPO


@pytest.fixture(scope="module")
def executable():
    def write(path: Path, content: str) -> Path:
        path.write_text(content)
        path.chmod(0o755)
        return path
    return write


@pytest.fixture(scope="module")
def run():
    def invoke(command, env, expected=0, stdin=None, timeout=120):
        result = subprocess.run(command, env=env, text=True, input=stdin,
                                capture_output=True, timeout=timeout)
        assert result.returncode == expected, (
            f"{command[0]} exited {result.returncode} (expected {expected}):\n"
            f"{result.stdout}\n{result.stderr}"
        )
        return result
    return invoke
