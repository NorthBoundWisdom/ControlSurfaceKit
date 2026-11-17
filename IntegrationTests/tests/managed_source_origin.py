#!/usr/bin/env python3
"""Actual main-graph origin/marker rejection, preserving all managed source bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    args.evidence.mkdir(parents=True, exist_ok=False)
    source = ROOT / 'build/seed/SurfacePlugins'
    marker = source / '.git/integration-surface-plugins-manager.json'
    records, failures = [], []

    def git(*arguments):
        return subprocess.check_output(['git', '-C', str(source), *arguments], text=True).strip()

    def snapshot():
        digest = hashlib.sha256()
        for raw in sorted(p for p in subprocess.check_output(['git', '-C', str(source), 'ls-files', '-z']).split(b'\0') if p):
            file = source / raw.decode()
            assert file.is_file() and not file.is_symlink()
            digest.update(raw + b'\0' + hashlib.sha256(file.read_bytes()).digest())
        return dict(head=git('rev-parse', 'HEAD'), origin=git('remote', 'get-url', 'origin'),
                    tracked_content_sha256=digest.hexdigest(), marker_sha256=hashlib.sha256(marker.read_bytes()).hexdigest(),
                    config_sha256=hashlib.sha256((source / '.git/config').read_bytes()).hexdigest(),
                    status=git('status', '--porcelain=v1', '--untracked-files=all', '--ignored'))

    def check(name, action, expected):
        before = snapshot()
        command = [sys.executable, '-B', 'configs/surface_plugins_dependency.py', action]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        after = snapshot()
        ok = (result.returncode == 0) == expected and before == after
        records.append(dict(name=name, command=command, expected_success=expected, exit_code=result.returncode,
                            before=before, after=after, unchanged=before == after, stdout=result.stdout, stderr=result.stderr, passed=ok))
        if not ok:
            failures.append(name)

    original_origin, original_marker = git('remote', 'get-url', 'origin'), marker.read_bytes()
    baseline = snapshot()
    assert not baseline['status']
    try:
        for action in ['verify', 'ensure']:
            check('valid_origin_' + action, action, True)
        try:
            git('remote', 'set-url', 'origin', 'https://example.invalid/wrong-main-integration-source.git')
            for action in ['verify', 'ensure']:
                check('wrong_actual_origin_' + action, action, False)
        finally:
            git('remote', 'set-url', 'origin', original_origin)
        try:
            wrong_marker = json.loads(original_marker)
            wrong_marker['remote'] = 'https://example.invalid/wrong-main-ownership-marker.git'
            marker.write_text(json.dumps(wrong_marker, sort_keys=True) + '\n')
            for action in ['verify', 'ensure']:
                check('wrong_marker_remote_' + action, action, False)
        finally:
            marker.write_bytes(original_marker)
        for action in ['verify', 'ensure']:
            check('restored_exact_source_' + action, action, True)
    finally:
        assert snapshot() == baseline
        summary = dict(main_source_origin_checks='fail' if failures else 'pass', checks=len(records),
                       positive_checks=sum(row['expected_success'] for row in records),
                       negative_checks=sum(not row['expected_success'] for row in records),
                       failures=failures, final_identity_equals_original=snapshot() == baseline, records=records)
        (args.evidence / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        print(json.dumps({key: value for key, value in summary.items() if key != 'records'}, sort_keys=True))
    assert not failures, failures


if __name__ == '__main__':
    main()
