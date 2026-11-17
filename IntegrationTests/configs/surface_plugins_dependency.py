#!/usr/bin/env python3
"""Main integration SP dependency; unrelated to the authority bridge's old SP."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "configs"))
import managed_git_dependency as manager
LAYOUT = manager.DependencyLayout(name="SurfacePlugins", lock_file="configs/surface_plugins.lock.json",
    marker="integration-surface-plugins-manager.json", source_env="INTEGRATION_SURFACE_PLUGINS_SOURCE",
    legacy_source_env="INTEGRATION_SURFACE_PLUGINS_PATH")
def ensure(**kwargs):
    return manager.ensure_dependency(ROOT, layout=LAYOUT, **kwargs)
if __name__ == "__main__":
    raise SystemExit(manager.main(layout=LAYOUT, ensure=ensure))
