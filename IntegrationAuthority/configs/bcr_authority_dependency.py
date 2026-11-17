#!/usr/bin/env python3
"""Test-only authority source; acquisition never compiles a developer checkout."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "configs"))
import authority_source_manager as manager

LAYOUT = manager.DependencyLayout(
    name="BCR2000Dev", lock_file="configs/bcr_authority.lock.json",
    marker="bcr-authority-manager.json", source_env="BCR_AUTHORITY_SOURCE",
    legacy_source_env="BCR_AUTHORITY_PATH",
)

def ensure(**kwargs):
    return manager.ensure_dependency(ROOT, layout=LAYOUT, **kwargs)

if __name__ == "__main__":
    raise SystemExit(manager.main(layout=LAYOUT, ensure=ensure))
