#!/usr/bin/env python3
"""Two full original platform scenarios, one explicit journal-step checkpoint, real negative controls."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["runner", "fixture", "bridge", "helper", "sdk-root", "evidence"]:
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    args.evidence.mkdir(parents=True, exist_ok=True)
    assert hashlib.sha256(args.fixture.read_bytes()).hexdigest() == "546fbc2a6f1d20f9e116a91558f4dd67891bfaba797b9778e85d975fe4cd3384"
    cases = ["none", "retry_lost_action", "drop_authority_error", "wrong_render", "truncate_journal"]
    ledger = []
    for fault in cases:
        output = args.evidence / fault
        output.mkdir(exist_ok=True)
        artifact_path = output / "result.json"
        command = [str(args.runner.resolve()), str(args.fixture.resolve()), str(artifact_path.resolve()), fault,
                   str(args.bridge.resolve()), str(args.helper.resolve()), str(args.sdk_root.resolve()), str(output.resolve())]
        started = time.monotonic()
        result = subprocess.run(command, capture_output=True, text=True, timeout=20)
        elapsed = time.monotonic() - started
        (output / "stdout.log").write_text(result.stdout)
        (output / "stderr.log").write_text(result.stderr)
        artifact = json.loads(artifact_path.read_text())
        assert artifact["fullInventoryAcceptance"] is False
        rows = {row["id"]: row for row in artifact["rows"]}
        assert list(rows) == ["T24", "T25", "T27"]
        assert rows["T24"]["completeOriginalScenario"] is True and len(rows["T24"]["steps"]) == 1
        assert rows["T27"]["completeOriginalScenario"] is True and len(rows["T27"]["steps"]) == 2
        assert rows["T25"]["completeOriginalScenario"] is False
        assert rows["T25"]["unexecutedStepIndices"] == [1] and rows["T25"]["steps"][0]["index"] == 0
        assert sum(row["assertionsChecked"] for row in rows.values()) == 6
        assert all(step["status"] != "not_applicable" for row in rows.values() for step in row["steps"])
        auxiliary = artifact["auxiliaryUndo"]
        assert auxiliary["denied"]["ok"] is False and auxiliary["denied"]["error"]["code"] == "denied"
        assert auxiliary["denied_values"]["p1"] == 100 and auxiliary["denied"]["snapshot"]["can_undo"] is True
        assert auxiliary["allowed"]["ok"] is True and auxiliary["allowed_values"]["p1"] == 0
        assert auxiliary["allowed"]["snapshot"]["can_redo"] is True
        port = json.loads((output / "authority-port-ledger.json").read_text())
        for frame in port:
            snapshot = frame["response"].get("snapshot")
            if snapshot:
                assert snapshot["source"] == "mock" and snapshot["assignment_count"] == 0
                assert all(snapshot[key] == 0 for key in ["hardware_send_attempts", "monitor_output_calls", "forbidden_callbacks"])
        assert port[-1]["response"]["result"]["live_instances"] == 0
        if fault == "none":
            assert result.returncode == 0 and all(row["status"] == "pass" and not row["failures"] for row in rows.values())
            facts = rows["T24"]["transportFacts"]
            assert facts["client_errors"] == ["transport_unknown"] and facts["upstream_request_ids"] == [1]
            assert facts["lost_responses"] == 1 and facts["automatic_retry_attempts"] == 0
            assert len(rows["T24"]["actionJournal"]) == 1
            assert rows["T24"]["steps"][0]["after"]["simulation"]["control_source"] == "simulation"
            assert rows["T27"]["steps"][-1]["after"]["primary"]["rendered_value"] == 10
            assert rows["T27"]["steps"][-1]["after"]["primary"]["authority_error_visible"] is True
            assert rows["T25"]["steps"][0]["after"]["primary"]["control_sequence"] == "17"
            assert rows["T25"]["steps"][0]["after"]["primary"]["journal_gap"] is True
        else:
            assert result.returncode == 1
            required = {
                "retry_lost_action": ("T24", "remote_input:action_fire1_count"),
                "drop_authority_error": ("T27", "write_parameter:authority_error_visible"),
                "wrong_render": ("T27", "write_parameter:rendered_value"),
                "truncate_journal": ("T25", "overflow_journal:journal_gap"),
            }
            row, failure = required[fault]
            assert rows[row]["status"] == "fail" and failure in rows[row]["failures"]
            if fault == "retry_lost_action":
                assert len(rows["T24"]["actionJournal"]) == 2
                assert rows["T24"]["transportFacts"]["upstream_request_ids"] == [1, 2]
                assert "remote_input:automatic_action_replay_count" in rows["T24"]["failures"]
        ledger.append(dict(fault=fault, command=command, exit_code=result.returncode, elapsed_seconds=elapsed,
                           statuses={key: row["status"] for key, row in rows.items()},
                           failures={key: row["failures"] for key, row in rows.items()}, authority_commands=len(port)))
    summary = dict(stage="platform-checkpoints-not-final-j5", complete_original_scenarios=["T24", "T27"],
                   complete_scenarios_pass=2, explicit_partial_checkpoints=["T25:overflow_journal"],
                   executed_original_operations=4, original_assertions=6, nonmotor_undo_aux="pass",
                   negative_controls_real_failures=4, skipped_or_na_rows=0, full_17_35_acceptance=False, runs=ledger)
    (args.evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps({key: value for key, value in summary.items() if key != "runs"}, sort_keys=True))


if __name__ == "__main__":
    main()
