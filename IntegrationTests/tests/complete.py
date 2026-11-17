#!/usr/bin/env python3
"""Full unchanged fixture through real production providers and current Kit."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import time
import jsonschema


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['runner', 'fixture', 'bridge', 'helper', 'sdk-root', 'evidence']:
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--revision', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    spec = importlib.util.spec_from_file_location('original_validator', root / 'scripts/validate_controller_regression.py')
    validator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(validator)
    fixture = json.loads(args.fixture.read_text())
    assert hashlib.sha256(args.fixture.read_bytes()).hexdigest() == '546fbc2a6f1d20f9e116a91558f4dd67891bfaba797b9778e85d975fe4cd3384'
    expected_na = ['T03', 'T07', 'T08', 'T09', 'T10', 'T11', 'T13', 'T14', 'T16', 'T17', 'T19', 'T20', 'T21']
    failures = {
        'wrong_route': ('T12', 'route_generation'),
        'wrong_input_endpoint': ('T01', 'decoded_input_endpoint'),
        'wrong_origin': ('T30', 'provenance_preserved'),
        'qualification_upgrade': ('T30', 'qualification_upgraded'),
        'receipt_on_rejection': ('T15', 'sent_value'),
        'auto_enable_binding': ('T28', 'enable_binding_count'),
        'retry_lost_action': ('T24', 'action_fire1_count'),
        'drop_authority_error': ('T27', 'error_visible'),
        'wrong_render': ('T27', 'rendered_value'),
        'truncate_journal': ('T25', 'journal_gap'),
        'bypass_remote_permission': ('T18', 'authorization_rules_equal'),
        'accept_spoof': ('T23', 'manual_authority_granted'),
        'use_wall_clock': ('T26', 'monotonic_policy_preserved'),
    }
    args.evidence.mkdir(parents=True, exist_ok=True)
    runs = []
    for fault in ['none'] + list(failures):
        output = args.evidence / fault
        output.mkdir(exist_ok=False)
        command = [str(args.runner.resolve()), str(args.fixture.resolve()), str(output.resolve()), fault,
                   str(args.bridge.resolve()), str(args.helper.resolve()), str(args.sdk_root.resolve()), args.revision,
                   str(root / 'docs/controller-regression-results.schema.json')]
        started = time.monotonic()
        result = subprocess.run(command, capture_output=True, text=True, timeout=30)
        elapsed = time.monotonic() - started
        (output / 'stdout.log').write_text(result.stdout)
        (output / 'stderr.log').write_text(result.stderr)
        report = json.loads((output / 'report.json').read_text())
        checked = validator.validate_report(output / 'report.json', args.fixture)
        jsonschema.Draft202012Validator(json.loads((root / 'docs/controller-regression-results.schema.json').read_text())).validate(report)
        rows = {row['id']: row for row in report['results']}
        summary = json.loads((output / 'summary.json').read_text())
        assert [row['id'] for row in report['results'] if row['status'] == 'not_applicable'] == expected_na
        assert [(row['id'], step['index']) for row in report['results'] for step in row['steps'] if step['status'] == 'not_applicable'] == [('T25', 1)]
        assert summary['original_assertions_checked'] == 50
        assert len([step for row in report['results'] for step in row['steps'] if step['status'] != 'not_applicable']) == 35
        port = json.loads((output / 'authority-port-ledger.json').read_text())
        assert port[-1]['response']['result']['live_instances'] == 0
        assert all(port[-1]['response']['result']['no_io'][key] == 0 for key in ['hardware_send_attempts', 'monitor_output_calls', 'forbidden_callbacks'])
        snapshots = [row['response']['snapshot'] for row in port if isinstance(row['response'].get('snapshot'), dict)]
        assert snapshots and all(s['source'] == 'mock' and s['assignment_count'] == 0 for s in snapshots)
        assert all(all(s[key] == 0 for key in ['hardware_send_attempts', 'monitor_output_calls', 'forbidden_callbacks']) for s in snapshots)
        raw = json.loads((output / 'raw.json').read_text())
        assert raw['nonmotor_undo_aux']['denied']['error']['code'] == 'denied'
        assert raw['nonmotor_undo_aux']['denied_values'] == {'p1': 100} and raw['nonmotor_undo_aux']['allowed_values'] == {'p1': 0}
        assert raw['nonmotor_undo_aux']['denied']['snapshot']['can_undo'] and raw['nonmotor_undo_aux']['allowed']['snapshot']['can_redo']
        failed = {key: [step['reason'] for step in row['steps'] if step['status'] == 'fail'] for key, row in rows.items() if row['status'] == 'fail'}
        if fault == 'none':
            endpoint_aux = raw['endpoint_auxiliary']
            assert endpoint_aux['separate_from_fixture'] and endpoint_aux['passed']
            attached = endpoint_aux['attach_only']
            assert attached['attempts'] == [] and attached['decoded_inputs'] == []
            detail = endpoint_aux['after_explicit_input_and_display']
            original = detail['attached_evidence'][0]['original_descriptor']
            actual = detail['attached_evidence'][0]['actual_connection_native_endpoint']
            assert original == actual and original['qualification'] is None and original['origin'] == 'remoteVirtual'
            event = detail['decoded_inputs'][0]['event']
            assert event['endpoint']['transport_origin'] == original['origin'] and event['endpoint']['endpoint_id'] == original['input']
            assert detail['preflight_records'][0]['plan']['common_endpoint']['origin'] == original['origin']
            assert detail['preflight_records'][0]['plan']['full_captured_evidence']['endpoint'] == original
            assert detail['attempts'][0]['successful_send'] and detail['native_received_display_packets'] == 1
            assert result.returncode == 0 and summary['scenarios_pass'] == 17 and summary['applicable_steps_pass'] == 35 and not failed
            assert checked['assertions_checked'] == 50 and checked['conformance'] == 'pass'
            for row in raw['raw_steps']:
                for device in row['devices']:
                    assert device['knob_display_capability'] is False
                    caps = device['profile_capabilities']
                    assert ('input.relative' in caps) == (device['mode'] == 'relative')
                    assert ('input.absolute' in caps) == (device['mode'] == 'absolute')
                    for decoded in device['decoded_inputs']:
                        event, native = decoded['event'], decoded['native_endpoint']
                        assert event['endpoint']['endpoint_id'] == native['input']
                        assert event['endpoint']['transport_origin'] == native['origin']
                        assert event['source'] == device['source']
                        assert 'address' in decoded['raw_packet']
                    for observation in device['observations']:
                        assert observation['source'] == device['source'] and observation['evidence'] == 'deviceReport'
                        assert observation['endpoint']['endpoint_id'] is not None
                    for attempt in device['attempts']:
                        assert attempt['affected_elements'] == ['lamp'] and attempt['native_address'] == 'lamp.output'
                        assert attempt['actual_attempt'] is True
                        assert attempt['receipt_plan']['source'] == device['source']
                        assert attempt['receipt_plan']['common_endpoint']['endpoint_id'] is not None
                    for preflight in device['preflight_records']:
                        assert preflight['plan'] == preflight['proof_plan']
                        assert preflight['plan']['required_directions'] == ['display']
                        assert preflight['plan']['affected_elements'] == ['lamp']
        else:
            scenario, metric = failures[fault]
            assert result.returncode == 1 and any(metric in reason for reason in failed.get(scenario, [])), (fault, failed)
        runs.append(dict(fault=fault, command=command, exit_code=result.returncode, elapsed_seconds=elapsed,
                         validation=checked, failures=failed, authority_commands=len(port)))
    source_files = sorted((root / 'IntegrationTests').rglob('*.swift'))
    source_files = [p for p in source_files if 'build' not in p.relative_to(root / 'IntegrationTests').parts]
    ledger = dict(stage='full-minimal-device-j5', complete_scenarios=17, applicable_steps=35, whole_physical_na=expected_na,
                  step_na=[dict(scenario='T25', index=1, physical_feature='motor')], assertions=50,
                  negative_controls_real_failures=len(failures), fixture_sha256=hashlib.sha256(args.fixture.read_bytes()).hexdigest(),
                  under_test_kit=args.revision, source_hashes={str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in source_files}, runs=runs)
    (args.evidence / 'summary.json').write_text(json.dumps(ledger, indent=2) + '\n')
    print(json.dumps({key: value for key, value in ledger.items() if key not in ['source_hashes', 'runs']}, sort_keys=True))


if __name__ == '__main__':
    main()
