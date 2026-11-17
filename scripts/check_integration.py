#!/usr/bin/env python3
"""Run the independent test-only J5 graphs once, preserving every command/result."""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def git(path, *args):
    return subprocess.check_output(['git', '-C', str(path), *args], text=True).strip()


def source_identity(path):
    files = subprocess.check_output(['git', '-C', str(path), 'ls-files', '-z']).split(b'\0')
    digest = hashlib.sha256()
    for raw in sorted(p for p in files if p):
        file = path / os.fsdecode(raw)
        if file.is_symlink() or not file.is_file():
            raise RuntimeError('Managed tracked source must be a regular file: ' + str(file))
        digest.update(raw + b'\0' + hashlib.sha256(file.read_bytes()).digest())
    markers = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (path / '.git').glob('*manager.json')}
    return dict(revision=git(path, 'rev-parse', 'HEAD'), remote=git(path, 'remote', 'get-url', 'origin'),
                status=git(path, 'status', '--porcelain=v1', '--untracked-files=all'),
                tracked_files=len([p for p in files if p]), tracked_content_sha256=digest.hexdigest(), markers=markers)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, default=ROOT / 'build/j5-integration')
    parser.add_argument('--scratch-name', default='swiftpm', help='Independent build leaf under each test graph build directory')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+', args.scratch_name):
        parser.error('scratch-name must be a safe directory leaf')
    scratch = 'build/' + args.scratch_name
    evidence = args.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=False)
    started = time.monotonic()
    records = []
    inventory = {}
    ledger = evidence / 'commands.json'

    def run(label, command, cwd=ROOT, extra=None):
        index = len(records) + 1
        environment = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
        environment.update(extra or {})
        remaining = 300 - (time.monotonic() - started)
        if remaining <= 0:
            raise RuntimeError('Structural failure: integration exceeded five minutes')
        begin = time.monotonic()
        with (evidence / f'{index:02d}-{label}.log').open('w') as log:
            result = subprocess.run([str(part) for part in command], cwd=cwd, env=environment,
                                    stdout=log, stderr=subprocess.STDOUT, timeout=remaining)
        record = dict(label=label, command=[str(part) for part in command], cwd=str(cwd),
                      exit_code=result.returncode, elapsed_seconds=time.monotonic() - begin)
        records.append(record)
        ledger.write_text(json.dumps(records, indent=2) + '\n')
        print(json.dumps(record, sort_keys=True), flush=True)
        if result.returncode:
            raise RuntimeError('Integration command failed: ' + label)

    py = [sys.executable, '-B']
    authority = ROOT / 'IntegrationAuthority'
    main_graph = ROOT / 'IntegrationTests'
    host = authority / 'build/seed/BCR2000Dev'
    sources = [host, host / 'build/seed/SurfacePlugins', host / 'build/seed/ControlSurfaceKit', main_graph / 'build/seed/SurfacePlugins']
    initial_cache_state = {str(p.relative_to(ROOT)): p.exists() for p in sources + [authority / scratch, main_graph / scratch]}
    run('acquire-authority', py + ['configs/bcr_authority_dependency.py', 'ensure'], authority)
    run('acquire-authority-sp', py + ['configs/surface_plugins_dependency.py', 'ensure'], host)
    run('acquire-authority-kit', py + ['configs/control_surface_kit_dependency.py', 'ensure'], host)
    run('acquire-current-sp', py + ['configs/surface_plugins_dependency.py', 'ensure'], main_graph)
    run('verify-authority', py + ['configs/bcr_authority_dependency.py', 'verify'], authority)
    run('verify-current-sp', py + ['configs/surface_plugins_dependency.py', 'verify'], main_graph)
    for source in sources:
        before = source_identity(source)
        if before['status']:
            raise RuntimeError('Managed source is dirty')
        # These are immutable full-SHA shallow seeds, not developer checkouts.
        # Stable commit timestamps avoid rebuilding unchanged restored cache inputs.
        stamp = int(git(source, 'show', '-s', '--format=%ct', 'HEAD'))
        for raw in subprocess.check_output(['git', '-C', str(source), 'ls-files', '-z']).split(b'\0'):
            if raw:
                os.utime(source / os.fsdecode(raw), (stamp, stamp), follow_symlinks=False)
        after = source_identity(source)
        if before != after:
            raise RuntimeError('Source identity changed during mtime restoration')
        inventory[str(source.relative_to(ROOT))] = after
    fixture = ROOT / 'fixtures/controller-regression-v1.json'
    revision = git(ROOT, 'rev-parse', 'HEAD')
    bridge = authority / scratch / 'debug/AuthorityBridge'
    binaries = main_graph / scratch / 'debug'
    run('build-authority', ['swift', 'build', '--jobs', '2', '--product', 'AuthorityBridge', '--build-path', scratch], authority, {'BCR_PORTABLE_BUILD': '1'})
    run('build-main-products', ['swift', 'build', '--jobs', '2', '--build-path', scratch], main_graph)
    run('managed-boundaries', py + ['tests/managed_source_boundaries.py', '--evidence', evidence / 'managed-boundaries'], authority)
    run('main-source-origin', py + ['tests/managed_source_origin.py', '--evidence', evidence / 'main-source-origin'], main_graph)
    run('authority-smoke', py + ['tests/smoke.py', '--bridge', bridge, '--evidence', evidence / 'authority-smoke'], authority)
    run('interactive-framing', py + ['tests/interactive_framing.py', '--bridge', bridge, '--evidence', evidence / 'interactive-framing'], authority)
    run('j3-checkpoint', py + ['tests/checkpoint.py', '--runner', binaries / 'CheckpointRunner', '--fixture', fixture, '--evidence', evidence / 'j3-checkpoint'], main_graph)
    common = ['--fixture', fixture, '--bridge', bridge, '--helper', main_graph / 'tests/action_transport.py', '--sdk-root', main_graph / 'build/seed/SurfacePlugins/clients/python']
    run('platform-checkpoint', py + ['tests/platform_checkpoint.py', '--runner', binaries / 'PlatformCheckpointRunner', *common, '--evidence', evidence / 'platform-checkpoint'], main_graph)
    run('control-checkpoint', py + ['tests/control_checkpoint.py', '--runner', binaries / 'ControlCheckpointRunner', *common, '--evidence', evidence / 'control-checkpoint'], main_graph)
    run('codec-boundary', [binaries / 'CodecBoundaryRunner', evidence / 'codec-boundary.json'], main_graph)
    run('full-original-scenarios', py + ['tests/complete.py', '--runner', binaries / 'CompleteScenarioRunner', *common, '--revision', revision, '--evidence', evidence / 'complete'], main_graph)
    run('postverify-authority', py + ['configs/bcr_authority_dependency.py', 'verify'], authority)
    run('postverify-current-sp', py + ['configs/surface_plugins_dependency.py', 'verify'], main_graph)
    for source in sources:
        if source_identity(source) != inventory[str(source.relative_to(ROOT))]:
            raise RuntimeError('Managed source identity changed after execution')
    elapsed = time.monotonic() - started
    summary = dict(artifact='j5-independent-integration', elapsed_seconds=elapsed, commands=len(records),
                   under_test_kit=revision, sources=inventory, fixture_sha256=hashlib.sha256(fixture.read_bytes()).hexdigest(),
                   complete=json.loads((evidence / 'complete/summary.json').read_text()),
                   scratch_graphs=[str((authority / scratch).relative_to(ROOT)), str((main_graph / scratch).relative_to(ROOT))],
                   initial_cache_state=initial_cache_state,
                   qualification='test-only-fake-device', no_hardware=True)
    (evidence / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    if elapsed > 300:
        raise RuntimeError('Structural failure: integration exceeded five minutes')
    print(f'INTEGRATION_CHECK_PASS elapsed_seconds={elapsed:.3f}', flush=True)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
