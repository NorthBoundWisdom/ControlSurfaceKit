#!/usr/bin/env python3
"""Run only the declared J3 checkpoint; not a30-row conformance report."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runner", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    args.evidence.mkdir(parents=True, exist_ok=True)
    fixture = json.loads(args.fixture.read_text())
    sha = hashlib.sha256(args.fixture.read_bytes()).hexdigest()
    assert sha == "546fbc2a6f1d20f9e116a91558f4dd67891bfaba797b9778e85d975fe4cd3384"
    selected = ["T12", "T28", "T30"]
    expected_steps = {row["id"]: [step["operation"] for step in row["steps"]]
                      for row in fixture["scenarios"] if row["id"] in selected}
    records = []
    for fault in ["none", "wrong_route", "wrong_binding"]:
        artifact_path = args.evidence / (fault + ".json")
        command = [str(args.runner.resolve()), str(args.fixture.resolve()), str(artifact_path.resolve()), fault]
        started = time.monotonic()
        result = subprocess.run(command, capture_output=True, text=True, timeout=10)
        elapsed = time.monotonic() - started
        (args.evidence / (fault + ".stdout.log")).write_text(result.stdout)
        (args.evidence / (fault + ".stderr.log")).write_text(result.stderr)
        artifact = json.loads(artifact_path.read_text())
        assert artifact["artifact"] == "minimal-device-j3-checkpoint-only"
        assert artifact["fullInventoryAcceptance"] is False
        assert artifact["selectedScenarioIDs"] == selected
        assert [row["id"] for row in artifact["rows"]] == selected
        assert sum(len(row["steps"]) for row in artifact["rows"]) == 7
        assert sum(row["assertionsChecked"] for row in artifact["rows"]) == 9
        for row in artifact["rows"]:
            assert [step["operation"] for step in row["steps"]] == expected_steps[row["id"]]
            assert row["capabilityPhysicalRoles"] == ["knob", "button", "lamp"]
            assert row["qualificationRecordCount"] == 0
            assert all(step["status"] != "not_applicable" for step in row["steps"])
        by_id = {row["id"]: row for row in artifact["rows"]}
        if fault == "none":
            assert result.returncode == 0
            assert all(row["status"] == "pass" and not row["failedAssertions"] for row in artifact["rows"])
            assert all(step["status"] == "pass" for row in artifact["rows"] for step in row["steps"])
            route = by_id["T12"]
            assert route["steps"][0]["after"]["primary"]["pending_display_count"] == 1
            assert route["steps"][1]["after"]["primary"]["pending_display_count"] == 0
            assert len(route["revokedIDs"]) == 1 and route["pendingIDs"] == []
            assert route["steps"][-1]["after"]["primary"]["old_authorization_valid"] is False
            assert by_id["T30"]["attachmentOrigins"] == ["remoteVirtual", "physicalUSB"]
            assert by_id["T30"]["endpointDeviceID"] is None
            assert all(row["sourceSequence"] == "0" for row in artifact["rows"])
        else:
            assert result.returncode == 1
            target = by_id["T12" if fault == "wrong_route" else "T28"]
            assert target["status"] == "fail"
            if fault == "wrong_route":
                assert "flush:route_generation" in target["failedAssertions"]
                assert "flush:old_authorization_valid" in target["failedAssertions"]
            else:
                assert target["failedAssertions"].count("receive_unconfigured:enable_binding_count") == 2
        records.append(dict(fault=fault, command=command, exit_code=result.returncode, elapsed_seconds=elapsed,
                            scenario_statuses={row["id"]: row["status"] for row in artifact["rows"]},
                            failed_assertions={row["id"]: row["failedAssertions"] for row in artifact["rows"]}))
    summary = dict(artifact="j3-checkpoint-evidence-not-final-j5", checkpoint_scenarios=3,
                   checkpoint_steps=7, original_assertions_checked=9,
                   positive_pass=3, positive_fail=0, skips=0, not_applicable=0,
                   negative_controls_real_failures=2, fixture_sha256=sha, runs=records,
                   full_30_row_report=False, other_scenarios_not_tested_not_classified=True)
    (args.evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps({key: summary[key] for key in summary if key != "runs"}, sort_keys=True))


if __name__ == "__main__":
    main()
