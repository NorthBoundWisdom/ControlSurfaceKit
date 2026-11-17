#!/usr/bin/env python3
"""Real isolated mutations of this prototype's owned cache; never developer sources."""
import argparse
import json
import os
from pathlib import Path
import stat
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "configs"))
import bcr_authority_dependency as entry


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    args.evidence.mkdir(parents=True, exist_ok=True)
    host = ROOT / "build/seed/BCR2000Dev"
    records = []

    def verify(name, expected):
        command = [sys.executable, "-B", "configs/bcr_authority_dependency.py", "verify"]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        records.append(dict(name=name, command=command, expected_success=expected,
                            exit_code=result.returncode, stdout=result.stdout, stderr=result.stderr))
        assert (result.returncode == 0) == expected, records[-1]

    verify("legal_nested_original_seeds", True)
    unknown = host / "build/unknown-ignored.txt"
    assert not unknown.exists()
    try:
        unknown.write_text("negative control\n")
        verify("unknown_ignored_build_file", False)
    finally:
        unknown.unlink()
    extra = host / "build/seed/ExtraSeed"
    assert not extra.exists()
    try:
        extra.mkdir()
        verify("extra_seed", False)
    finally:
        extra.rmdir()
    child = host / "build/seed/SurfacePlugins"
    dirty = child / "negative-untracked.txt"
    assert not dirty.exists()
    try:
        dirty.write_text("negative control\n")
        verify("dirty_child_source", False)
    finally:
        dirty.unlink()

    def git(*arguments, input=None):
        return subprocess.check_output(["git", "-C", str(child), *arguments], input=input).decode().strip()

    original_head = git("rev-parse", "HEAD")
    tree = git("rev-parse", "HEAD^{tree}")
    commit = (f"tree {tree}\nauthor Boundary Test <invalid@example.invalid> 0 +0000\n"
              "committer Boundary Test <invalid@example.invalid> 0 +0000\n\nIsolated wrong-revision control\n").encode()
    wrong_head = git("hash-object", "-t", "commit", "-w", "--stdin", input=commit)
    try:
        git("update-ref", "--no-deref", "HEAD", wrong_head)
        verify("wrong_child_revision", False)
    finally:
        git("update-ref", "--no-deref", "HEAD", original_head)
    original_origin = git("remote", "get-url", "origin")
    try:
        git("remote", "set-url", "origin", "https://example.invalid/not-the-declared-source.git")
        verify("wrong_child_origin", False)
    finally:
        git("remote", "set-url", "origin", original_origin)
    lock = host / "build/seed/.SurfacePlugins.lock"
    lock_bytes, lock_mode = lock.read_bytes(), stat.S_IMODE(lock.stat().st_mode)
    try:
        lock.unlink()
        lock.symlink_to("nonexistent-lock-target")
        verify("child_lock_symlink", False)
    finally:
        lock.unlink()
        lock.write_bytes(lock_bytes)
        lock.chmod(lock_mode)
    link = ROOT / "build/negative-source-root-link"
    assert not link.exists() and not link.is_symlink()
    try:
        link.symlink_to(host, target_is_directory=True)
        try:
            entry.manager._owned(link, dict(os.environ), entry.LAYOUT)
        except entry.manager.DependencyError as error:
            records.append(dict(name="managed_source_root_symlink", expected_success=False, rejected=True, error=str(error)))
        else:
            raise AssertionError("symlink source root was accepted")
    finally:
        link.unlink()
    verify("restored_exact_clean_source", True)
    summary = dict(managed_source_boundary_checks="pass", positive_checks=2, negative_checks=7, records=records)
    (args.evidence / "managed-source-boundaries.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps({key: summary[key] for key in ("managed_source_boundary_checks", "positive_checks", "negative_checks")}, sort_keys=True))


if __name__ == "__main__":
    main()
