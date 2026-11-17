#!/usr/bin/env python3
"""Actual authority revocation, closed request parsing and monotonic production policy."""
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
    ledger = []
    for fault in ["none", "bypass_remote_permission", "accept_spoof", "use_wall_clock"]:
        output = args.evidence / fault
        output.mkdir(exist_ok=True)
        result_path = output / "result.json"
        command = [str(args.runner.resolve()), str(args.fixture.resolve()), str(result_path.resolve()), fault,
                   str(args.bridge.resolve()), str(args.helper.resolve()), str(args.sdk_root.resolve()), str(output.resolve())]
        started = time.monotonic()
        result = subprocess.run(command, capture_output=True, text=True, timeout=20)
        elapsed = time.monotonic() - started
        (output / "stdout.log").write_text(result.stdout)
        (output / "stderr.log").write_text(result.stderr)
        artifact = json.loads(result_path.read_text())
        assert artifact["fullInventoryAcceptance"] is False
        rows = {row["id"]: row for row in artifact["rows"]}
        assert list(rows) == ["T18", "T23", "T26"]
        assert all(row["completeOriginalScenario"] for row in rows.values())
        assert sum(len(row["steps"]) for row in rows.values()) == 6
        assert sum(row["assertionsChecked"] for row in rows.values()) == 6
        assert all(step["status"] != "not_applicable" for row in rows.values() for step in row["steps"])
        port = json.loads((output / "authority-port-ledger.json").read_text())
        writes = [row for row in port if row["request"]["op"] == "write"]
        assert len(writes) == 2
        for row in port:
            snapshot = row["response"].get("snapshot")
            if snapshot:
                assert snapshot["source"] == "mock" and snapshot["assignment_count"] == 0
                assert all(snapshot[key] == 0 for key in ["hardware_send_attempts", "monitor_output_calls", "forbidden_callbacks"])
        assert port[-1]["response"]["result"]["live_instances"] == 0
        aux = rows["T23"]["providerFacts"]["spoof_parser_auxiliary"]
        forged, baseline = json.loads(aux["forged_arguments_canonical"]), json.loads(aux["baseline_arguments_canonical"])
        assert aux["removed_keys"] == ["origin"] and forged.pop("origin") == "hardware" and forged == baseline
        assert aux["other_fields_byte_preserved"] and all(aux["other_fields_byte_preserved"].values())
        assert aux["forged_parse_error"] == "invalid_argument" and aux["baseline_parse_result"] == "input"
        assert aux["hardware_validation_error"] == "permission_denied"
        assert aux["action_events_before_aux"] == aux["action_events_after_aux"] == 0
        controls = rows["T23"]["providerFacts"]["approval_controls"]
        assert controls["untrusted_before"]["policy"] == "localOrigins" and controls["untrusted_before"]["state"] == "waitingApproval"
        assert controls["ordinary_remote_error"]["code"] == "permissionDenied"
        assert controls["ordinary_remote_after"]["state"] == "waitingApproval" and controls["ordinary_remote_after"]["journal"] == []
        assert controls["true_local_hardware_after"]["state"] == "running"
        assert controls["true_local_hardware_after"]["status_key"] == "agent.mock.approved"
        assert len(controls["true_local_hardware_after"]["journal"]) == 1
        assert controls["original_witness_after_isolated_controls"] == controls["untrusted_before"]
        if fault == "none":
            assert result.returncode == 0 and all(row["status"] == "pass" and not row["failures"] for row in rows.values())
            assert [row["response"]["error"]["code"] for row in writes] == ["denied", "denied"]
            assert all(row["response"]["snapshot"]["values"]["p1"] == 0 for row in writes)
            assert rows["T18"]["providerFacts"]["write_decisions"] == dict(local="denied", remote="denied")
            assert rows["T23"]["providerFacts"]["remote_rejection"] == "invalid_argument"
            assert rows["T23"]["actionJournal"] == [] and rows["T23"]["providerFacts"]["remote_dispatch_origins"] == []
            assert rows["T23"]["providerFacts"]["untrusted_approval_witness_after"] == controls["untrusted_before"]
            assert rows["T23"]["providerFacts"]["untrusted_approval_events"] == []
            assert rows["T26"]["providerFacts"]["clock_errors"] == []
            assert rows["T26"]["providerFacts"]["policy_monotonic"] == rows["T26"]["providerFacts"]["policy_server_time"] == 0.2
            assert rows["T26"]["providerFacts"]["clock_witness_slots"][0]["updated_at"] <= 0.2
        else:
            assert result.returncode == 1
            failures = {
                "bypass_remote_permission": ("T18", "write_parameter:authorization_rules_equal"),
                "accept_spoof": ("T23", "remote_input:manual_authority_granted"),
                "use_wall_clock": ("T26", "advance_time:monotonic_policy_preserved"),
            }
            key, failure = failures[fault]
            assert rows[key]["status"] == "fail" and failure in rows[key]["failures"]
            if fault == "bypass_remote_permission":
                assert writes[1]["response"]["ok"] is True and writes[1]["response"]["snapshot"]["values"]["p1"] == 64
                assert "write_parameter:requiresJ4Dispatch" in rows[key]["failures"]
            if fault == "accept_spoof":
                assert len(rows[key]["actionJournal"]) == 1 and rows[key]["providerFacts"]["remote_dispatch_origins"] == ["hardware"]
                assert rows[key]["providerFacts"]["untrusted_approval_witness_after"]["status_key"] == "agent.mock.approved"
                assert any(event["fields"]["statusKey"] == "agent.mock.approved" for event in rows[key]["providerFacts"]["untrusted_approval_events"])
            if fault == "use_wall_clock":
                assert rows[key]["providerFacts"]["clock_errors"]
        ledger.append(dict(fault=fault, command=command, exit_code=result.returncode, elapsed_seconds=elapsed,
                           statuses={key: row["status"] for key, row in rows.items()},
                           failures={key: row["failures"] for key, row in rows.items()}, authority_commands=len(port)))
    summary = dict(stage="authority-parser-clock-checkpoints-not-final-j5", complete_original_scenarios=["T18", "T23", "T26"],
                   positive_pass=3, executed_original_operations=6, original_assertions=6,
                   negative_controls_real_failures=3, skipped_or_na_rows=0, full_17_35_acceptance=False, runs=ledger)
    (args.evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps({key: value for key, value in summary.items() if key != "runs"}, sort_keys=True))


if __name__ == "__main__":
    main()
