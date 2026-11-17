#!/usr/bin/env python3
"""Main integration SP dependency; unrelated to the authority bridge's old SP."""
from pathlib import Path
import os
import sys
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "configs"))
import managed_git_dependency as manager
LAYOUT = manager.DependencyLayout(name="SurfacePlugins", lock_file="configs/surface_plugins.lock.json",
    marker="integration-surface-plugins-manager.json", source_env="INTEGRATION_SURFACE_PLUGINS_SOURCE",
    legacy_source_env="INTEGRATION_SURFACE_PLUGINS_PATH")
def _verify_actual_origin(spec, environ):
    parent = manager._parent(ROOT, create=False, layout=LAYOUT)
    with manager._exclusive(parent, read_only=True, layout=LAYOUT):
        source = ROOT / LAYOUT.cache_path
        owned = manager._owned(source, environ, LAYOUT)
        if owned["remote"] != spec["remote"]:
            raise manager.DependencyError("Main integration ownership remote differs from the approved lock")
        if manager._git(source, "remote", "get-url", "origin", environ=environ) != spec["remote"]:
            raise manager.DependencyError("Main integration source origin differs from its declared remote")


def ensure(**kwargs):
    environ = dict(os.environ if kwargs.get("environ") is None else kwargs["environ"])
    spec = manager._spec(ROOT, LAYOUT)
    destination = ROOT / LAYOUT.cache_path
    # Refuse an altered existing source before the base manager can consider an
    # update/materialization. Verification never repairs or rewrites its origin.
    if destination.exists() or destination.is_symlink():
        _verify_actual_origin(spec, environ)
    result = manager.ensure_dependency(ROOT, layout=LAYOUT, **kwargs)
    _verify_actual_origin(spec, environ)
    return result
if __name__ == "__main__":
    raise SystemExit(manager.main(layout=LAYOUT, ensure=ensure))
