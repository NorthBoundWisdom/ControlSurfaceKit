#!/usr/bin/env python3
"""Enforce the evaluated package DAG and parsed Swift source boundaries.

Uses only Python stdlib and the installed Swift toolchain. AST diagnostics are
fail-closed. This is a mechanical guardrail, not a semantic purity proof.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DAG = {
    "SurfaceDeviceContracts": set(),
    "SurfaceBindingContext": {"SurfaceDeviceContracts"},
    "SurfaceConnectionState": {"SurfaceBindingContext"},
    "SurfaceFeedbackPlanning": {"SurfaceConnectionState"},
    "SurfaceDeviceConformance": {"SurfaceDeviceContracts", "SurfaceBindingContext", "SurfaceConnectionState", "SurfaceFeedbackPlanning"},
}
CONFORMANCE = "SurfaceDeviceConformance"
# The public package structure is intentional. Tests may add targets, production
# dependencies must match the approved boundaries, regardless of manifest layout.


def dependency_name(entry):
    for kind in ("byName", "target"):
        if kind in entry:
            value = entry[kind]
            return value[0] if isinstance(value, list) else value
    raise ValueError("external or unknown target dependency")


def check_manifest(manifest):
    errors = []
    if manifest.get("dependencies"):
        errors.append("package: external dependencies (including SurfacePlugins) are forbidden")
    targets = manifest.get("targets", [])
    production = {t["name"]: t for t in targets if t.get("type") != "test"}
    if set(production) != set(DAG):
        errors.append("package: expected the five approved production/test-support targets")
    for name, target in production.items():
        if name not in DAG:
            continue
        try:
            dependencies = {dependency_name(d) for d in target.get("dependencies", [])}
        except ValueError as error:
            errors.append(f"{name}: {error}")
            continue
        if dependencies != DAG[name]:
            errors.append(f"{name}: invalid dependency direction: {sorted(dependencies)}")
        if target.get("type") != "regular" or target.get("pluginUsages"):
            errors.append(f"{name}: only regular Swift targets without plugins are allowed")
        if target.get("settings"):
            errors.append(f"{name}: per-target compiler/linker overrides are forbidden")
        if target.get("path") not in (None, "Sources/" + name):
            errors.append(f"{name}: source path must stay inside its target")
    for product in manifest.get("products", []):
        names = set(product.get("targets", []))
        if CONFORMANCE in names and names != {CONFORMANCE}:
            errors.append("package: test support cannot be bundled with production targets")
    return errors


def parse_files(paths):
    if not paths:
        return {}
    command = ["swiftc", "-frontend", "-dump-parse", *[argument for path in paths for argument in ("-primary-file", str(path))]]
    result = subprocess.run(command, capture_output=True, text=True)
    output = result.stdout + result.stderr
    if result.returncode or re.search(r"\berror:", output):
        raise ValueError("Swift parser rejected input: " + output[:2000])
    # Each file is parsed by Swift; no regex attempts to parse Swift declarations.
    parts = re.split(r'\(source_file "([^"\n]+)"', output)
    parsed = {parts[i]: parts[i + 1] for i in range(1, len(parts), 2)}
    if set(parsed) != {str(p) for p in paths}:
        raise ValueError("Swift parser output format changed or omitted a source file")
    return parsed


def strip_comments(source):
    # Retain strings: device/protocol knowledge in literal data is also forbidden.
    # Swift's AST handles declarations. This tokenizer only strips comments while
    # preserving quoted strings and line numbers, including nested block comments.
    tokens = re.compile(r'(?s)(""".*?"""|"(?:\\.|[^"\\])*"|//[^\n]*|/\*|\*/)')
    depth, end, result = 0, 0, []
    for match in tokens.finditer(source):
        chunk = source[end:match.start()]
        result.append(re.sub(r"[^\n]", " ", chunk) if depth else chunk)
        token = match.group()
        if token == "/*":
            depth += 1
            result.append("  ")
        elif token == "*/" and depth:
            depth -= 1
            result.append("  ")
        elif depth or token.startswith("//"):
            result.append(re.sub(r"[^\n]", " ", token))
        else:
            result.append(token)
        end = match.end()
    tail = source[end:]
    result.append(re.sub(r"[^\n]", " ", tail) if depth else tail)
    return "".join(result)


RULES = [
    ("device knowledge", r"\b(?:BCR\w*|XTouch\w*|X_Touch\w*|X-Touch|Behringer|Mackie|CompactHardware\w*)\b"),
    ("protocol address/encoding", r"\b(?:0[xX][0-9a-fA-F_]+|MIDI\w*|midi\w*|NRPN\w*|SysEx\w*|sysex\w*|ProgramChange|controlChange|noteOn|noteOff)\b"),
    ("protocol address field", r"\b(?:statusByte|dataByte|midiChannel|controllerNumber|noteNumber|ccNumber)\b"),
    ("clock/process access", r"\b(?:Date|NSDate|CFAbsoluteTimeGetCurrent|CACurrentMediaTime|ProcessInfo|mach_absolute_time|clock_gettime|gettimeofday|ContinuousClock|SuspendingClock|DispatchTime|DispatchWallTime)\b"),
    ("scheduling or asynchronous runtime", r"\b(?:Timer|DispatchQueue|RunLoop|Task|Thread|pthread\w*|sleep|usleep|nanosleep|async|await|OperationQueue)\b"),
    ("I/O or environment", r"\b(?:URLSession|URLRequest|FileManager|FileHandle|InputStream|OutputStream|Process|UserDefaults|NotificationCenter|getenv|fopen|socket|print|readLine)\b"),
    ("duplicate parameter/business authority", r"\b(?:ParameterDefinition|ParameterQuantizer|ParameterStore|ParameterEngine|SurfaceControlSession|ControlContractSession|AgentPlugin|RobotPlugin|ChassisPlugin|ParameterOutputPlugin|quantize|quantise)\b"),
    ("conditional compilation hides unverified code", r"(?m)^\s*#(?:if|elseif|else|endif)\b"),
    ("mutable reference storage", r"\b(?:NSMutable\w*|NSCache|NSMapTable|NSHashTable|NSLock|NSRecursiveLock|NSCondition)\b"),
    ("unchecked concurrency or global isolation", r"@(?:unchecked|MainActor)|nonisolated\s*\(\s*unsafe\s*\)"),
]


def check_source(source, ast, target, path):
    errors = []
    allowed = {"Foundation"} | DAG[target]
    for module in re.findall(r'\(import_decl[^\n]*\bmodule="([^"]+)"', ast):
        if module.split(".")[0] not in allowed:
            errors.append(f"{path}: forbidden import {module}")
    for line in ast.splitlines():
        if "(var_decl " in line and not re.search(r"\blet\b", line):
            if line.startswith("  (var_decl ") or "top_level_global" in line or re.search(r"\bstatic\b", line):
                errors.append(f"{path}: global/static mutable state: {line.strip()}")
        if re.search(r"\((?:class_decl|actor_decl)\b", line):
            errors.append(f"{path}: reference/actor state is forbidden")
    text = strip_comments(source)
    for label, pattern in RULES:
        if re.search(pattern, text, flags=re.I if label == "device knowledge" else 0):
            errors.append(f"{path}: {label}")
    return errors


def check(root=ROOT):
    result = subprocess.run(["swift", "package", "--package-path", str(root), "dump-package"], capture_output=True, text=True)
    if result.returncode:
        raise ValueError("SwiftPM rejected manifest: " + result.stderr[:2000])
    manifest = json.loads(result.stdout)
    errors = check_manifest(manifest)
    paths = sorted((root / "Sources").rglob("*.swift"))
    parsed = parse_files(paths)
    for path in paths:
        parts = path.relative_to(root / "Sources").parts
        target = parts[0]
        if target not in DAG or path.is_symlink():
            errors.append(f"{path}: unknown target or symlinked source")
            continue
        errors.extend(check_source(path.read_text(), parsed[str(path)], target, str(path.relative_to(root))))
    for name in DAG:
        if not any(p.relative_to(root / "Sources").parts[0] == name for p in paths):
            errors.append(f"{name}: missing Swift source")
    return errors, len(paths)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    try:
        errors, count = check(args.root.resolve())
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(f"boundary-check: FAIL: {error}", file=sys.stderr)
        return 1
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(json.dumps({"boundary_check": "pass", "swift_files": count, "targets": len(DAG)}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
