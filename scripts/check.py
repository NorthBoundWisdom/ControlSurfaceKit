#!/usr/bin/env python3
"""Run the full local/CI check set once; no retries and no hardware."""
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
started = time.monotonic()
commands = [
    [sys.executable, "-B", "scripts/check_boundaries.py"],
    [sys.executable, "-B", "-m", "unittest", "discover", "-s", "scripts/tests", "-v"],
    [sys.executable, "-B", "-m", "unittest", "discover", "-s", "tools/tests", "-v"],
    [sys.executable, "-B", "-m", "unittest", "discover", "-s", "clients/python/tests", "-v"],
    [sys.executable, "-B", "scripts/validate_controller_regression.py"],
    [sys.executable, "-B", "scripts/validate_controller_regression_schemas.py"],
    ["swift", "test", "--build-path", "build/swiftpm"],
]
for command in commands:
    print("COMMAND " + " ".join(command), flush=True)
    result = subprocess.run(command, cwd=ROOT)
    if result.returncode:
        raise SystemExit(result.returncode)
elapsed = time.monotonic() - started
print(f"FULL_CHECK_PASS elapsed_seconds={elapsed:.3f}", flush=True)
if elapsed > 300:
    print("Structural failure: full checks exceeded five minutes", file=sys.stderr)
    raise SystemExit(1)
