#!/usr/bin/env python3
"""Prototype only: exercise actual production authority, not shared scenarios."""
import argparse
import json
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bridge", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    args.evidence.mkdir(parents=True, exist_ok=True)
    frames = []

    def add(op, arguments=None, instance="primary"):
        frames.append(dict(version=1, id=len(frames) + 1, op=op, instance=instance,
                           at=len(frames) / 10, arguments=arguments or {}))
        return len(frames) - 1

    def permissions(write=True, history=True):
        return dict(allows_write=write, allows_display=True,
                    identities=["local", "remote"] + (["history"] if history else []))

    created = add("create", {"definitions": [dict(id="p1", minimum=0, maximum=127, initial=0)]})
    add("permissions", permissions())
    written = add("write", dict(parameter="p1", canonical_value=100, identity="local"))
    add("end_history_group")
    add("permissions", permissions(write=False))
    denied = add("write", dict(parameter="p1", canonical_value=50, identity="remote"))
    add("permissions", permissions(history=False))
    undo_denied = add("undo")
    add("permissions", permissions())
    undone = add("undo")
    redone = add("redo")
    add("authority_reply", dict(parameter="p1", accepted=False, actual_value=10, reason="authority_denied"))
    rejected = add("write", dict(parameter="p1", canonical_value=100, identity="local"))
    corrected = add("snapshot")
    add("authority_reply", dict(parameter="p1", accepted=True))
    add("end_history_group")
    accepted_again = add("write", dict(parameter="p1", canonical_value=20, identity="local"))
    add("create", {"definitions": [dict(id="p1", minimum=0, maximum=127, initial=7)]}, instance="secondary")
    add("permissions", permissions(), instance="secondary")
    secondary = add("write", dict(parameter="p1", canonical_value=9, identity="remote"), instance="secondary")
    isolated = add("snapshot")
    forbidden = add("select_hardware", {})
    malformed = add("write", dict(parameter="p1", canonical_value=21, identity="local", unexpected=True))
    unchanged = add("snapshot")
    destroyed = add("destroy")
    absent = add("snapshot")
    add("destroy", instance="secondary")
    finished = add("finish")

    raw = b"".join(json.dumps(frame, allow_nan=False, separators=(",", ":")).encode() + b"\n" for frame in frames)
    started = time.monotonic()
    result = subprocess.run([str(args.bridge.resolve())], input=raw, capture_output=True, timeout=30)
    elapsed = time.monotonic() - started
    (args.evidence / "requests.jsonl").write_bytes(raw)
    (args.evidence / "responses.jsonl").write_bytes(result.stdout)
    (args.evidence / "stderr.log").write_bytes(result.stderr)
    assert result.returncode == 0, result.stderr.decode() + result.stdout.decode()
    responses = [json.loads(line) for line in result.stdout.splitlines()]
    assert len(responses) == len(frames)
    for request, response in zip(frames, responses):
        assert (response["version"], response["id"], response["instance"]) == (1, request["id"], request["instance"])
        if isinstance(response.get("snapshot"), dict):
            snapshot = response["snapshot"]
            assert snapshot["source"] == "mock" and snapshot["assignment_count"] == 0
            assert snapshot["input_epoch"] == request["instance"] + ".authority.epoch"
            assert all(snapshot[key] == 0 for key in ("hardware_send_attempts", "monitor_output_calls", "forbidden_callbacks"))
    def value(index):
        return responses[index]["snapshot"]["values"]["p1"]
    assert value(created) == 0
    assert value(written) == 100 and responses[written]["snapshot"]["can_undo"]
    assert responses[denied]["ok"] is False and responses[denied]["error"]["code"] == "denied" and value(denied) == 100
    assert responses[undo_denied]["ok"] is False and responses[undo_denied]["error"]["code"] == "denied" and value(undo_denied) == 100
    assert responses[undo_denied]["snapshot"]["can_undo"]
    assert value(undone) == 0 and responses[undone]["snapshot"]["can_redo"]
    assert value(redone) == 100
    assert responses[rejected]["ok"] is False and responses[rejected]["error"] == dict(code="authority_rejected", reason="authority_denied")
    assert value(rejected) == value(corrected) == 10
    assert value(accepted_again) == 20 and value(secondary) == 9 and value(isolated) == 20
    assert responses[forbidden]["ok"] is False and responses[forbidden]["error"]["code"] == "invalid_frame"
    assert responses[malformed]["ok"] is False and value(malformed) == value(unchanged) == 20
    assert responses[destroyed]["snapshot"] is None
    assert responses[absent]["ok"] is False and responses[absent]["snapshot"] is None
    assert responses[finished]["result"] == dict(commands=len(frames), live_instances=0,
                                                no_io=dict(hardware_send_attempts=0, monitor_output_calls=0, forbidden_callbacks=0))

    negative_results = []
    for name, payload, expected in [
        ("oversized", b"x" * 65537 + b"\n", "frame_size"),
        ("incomplete", b"{}", "incomplete_frame"),
        ("duplicate_request_id", raw.splitlines(keepends=True)[0] * 2, "header"),
    ]:
        negative = subprocess.run([str(args.bridge.resolve())], input=payload, capture_output=True, timeout=10)
        (args.evidence / (name + ".stdout.jsonl")).write_bytes(negative.stdout)
        (args.evidence / (name + ".stderr.log")).write_bytes(negative.stderr)
        output = [json.loads(line) for line in negative.stdout.splitlines()]
        assert negative.returncode != 0 and output[-1]["fatal"] and output[-1]["error"]["field"] == expected
        negative_results.append(dict(name=name, exit_code=negative.returncode, expected_error=expected))
    summary = dict(prototype_smoke="pass", command_frames=len(frames), negative_controls=negative_results,
                   actual_authority_checks=["create", "write", "permission_denied", "undo_revoked", "real_undo_redo",
                                            "external_rejection_actual10", "same_value_owner", "instance_isolation",
                                            "destroy_no_resurrection", "zero_device_io"],
                   shared_scenarios_executed=0, elapsed_seconds=elapsed)
    (args.evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, sort_keys=True))


if __name__ == "__main__":
    main()
