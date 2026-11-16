import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_boundaries as boundary

CASES = {
    "core_midi": ("import CoreMIDI", "forbidden import"),
    "appkit": ("@preconcurrency import AppKit", "forbidden import"),
    "swiftui": ("import SwiftUI", "forbidden import"),
    "network": ("import Network", "forbidden import"),
    "network_foundation": ("import FoundationNetworking", "forbidden import"),
    "specific_import": ("import struct AppKit.NSView", "forbidden import"),
    "class_import": ("import class FoundationNetworking.URLSession", "forbidden import"),
    "multiline_import": ("import\nNetwork", "forbidden import"),
    "conditional_import": ("#if canImport(CoreMIDI)\nimport CoreMIDI\n#endif", "conditional compilation"),
    "surface_plugins": ("import SurfacePluginContracts", "forbidden import"),
    "reverse_target": ("import SurfaceFeedbackPlanning", "forbidden import"),
    "test_support": ("import SurfaceDeviceConformance", "forbidden import"),
    "device_type": ("struct BCR2000Device: Sendable {}", "device knowledge"),
    "device_data": ('let name = "X-Touch One"', "device knowledge"),
    "address_literal": ("let address = 0xB0", "protocol address"),
    "address_field": ("let controllerNumber = 7", "protocol address field"),
    "midi_model": ("struct MIDIMessage: Sendable {}", "protocol address"),
    "date_call": ("let instant = Date()", "clock/process access"),
    "computed_clock": ("struct S: Sendable { var now: Double { Date().timeIntervalSince1970 } }", "clock/process access"),
    "date_alias": ("typealias ClockSource = Date", "clock/process access"),
    "dispatch_now": ("let instant = DispatchTime . now()", "clock/process access"),
    "process_clock": ("let instant = ProcessInfo.processInfo.systemUptime", "clock/process access"),
    "continuous_clock": ("let instant = ContinuousClock.now", "clock/process access"),
    "sleep": ("func pause() { usleep(10) }", "scheduling"),
    "timer": ("let timer = Timer()", "scheduling"),
    "async_task": ("func operation() async {}", "scheduling"),
    "file_io": ("let manager = FileManager.default", "I/O"),
    "network_io": ("let client = URLSession.shared", "I/O"),
    "top_level_var": ("var shared = 1", "global/static mutable"),
    "multiline_global": ("public\nvar shared: Int { 1 }", "global/static mutable"),
    "static_var": ("struct S: Sendable { static var shared = 1 }", "global/static mutable"),
    "mutable_reference_global": ("let shared = NSMutableArray()", "mutable reference storage"),
    "class_state": ("final class S {}", "reference/actor"),
    "actor_state": ("actor S {}", "reference/actor"),
    "parameter_store": ("struct ParameterStore: Sendable {}", "duplicate parameter"),
    "quantization": ("func quantize(_ x: Double) -> Double { x }", "duplicate parameter"),
    "control_session": ("struct SurfaceControlSession: Sendable {}", "duplicate parameter"),
    "business_plugin": ("struct AgentPlugin: Sendable {}", "duplicate parameter"),
    "unchecked": ("struct S: @unchecked Sendable {}", "unchecked concurrency"),
}


class SourceBoundaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # One parser process for the entire negative corpus; no per-case startup.
        cls.directory = tempfile.TemporaryDirectory()
        root = Path(cls.directory.name)
        cls.paths = {}
        for name, (source, _) in CASES.items():
            p = root / (name + ".swift")
            p.write_text(source + "\n")
            cls.paths[name] = p
        cls.safe = root / "safe.swift"
        cls.safe.write_text('''import Foundation
// A comment about Date(), MIDI, X-Touch and static var is not code.
/* Nested /* clock */ comment */
public struct NeutralValue: Sendable {
    public var count: Int
    public static let initial = 0
    public func changing() -> Int { var local = count; local += 1; return local }
}
''')
        cls.parsed = boundary.parse_files([*cls.paths.values(), cls.safe])

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def test_pure_value_and_local_mutation_are_allowed(self):
        self.assertEqual(boundary.check_source(self.safe.read_text(), self.parsed[str(self.safe)], "SurfaceDeviceContracts", "safe.swift"), [])

    def test_comments_do_not_hide_real_code(self):
        source = '/* Date() */ let real = Date()'
        self.assertIn("Date()", boundary.strip_comments(source))
        self.assertNotIn("/*", boundary.strip_comments(source))

    def test_nested_comments_are_stripped(self):
        self.assertEqual(boundary.strip_comments("/* one /* two */ end */ok").strip(), "ok")


def negative_case(name):
    def test(self):
        path = self.paths[name]
        errors = boundary.check_source(path.read_text(), self.parsed[str(path)], "SurfaceDeviceContracts", path.name)
        self.assertTrue(any(CASES[name][1] in error for error in errors), errors)
    return test


for name in CASES:
    setattr(SourceBoundaryTests, "test_reject_" + name, negative_case(name))


class ManifestBoundaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        result = subprocess.run(["swift", "package", "--package-path", str(boundary.ROOT), "dump-package"], capture_output=True, text=True, check=True)
        cls.manifest = json.loads(result.stdout)

    def modified(self):
        return copy.deepcopy(self.manifest)

    def test_actual_manifest_is_allowed(self):
        self.assertEqual(boundary.check_manifest(self.manifest), [])

    def test_feedback_direct_earlier_edges_are_explicit(self):
        target = next(t for t in self.manifest["targets"] if t["name"] == "SurfaceFeedbackPlanning")
        self.assertEqual({boundary.dependency_name(d) for d in target["dependencies"]},
                         {"SurfaceDeviceContracts", "SurfaceBindingContext", "SurfaceConnectionState"})

    def test_feedback_cannot_omit_its_required_contract_edge(self):
        value = self.modified()
        target = next(t for t in value["targets"] if t["name"] == "SurfaceFeedbackPlanning")
        target["dependencies"] = [d for d in target["dependencies"] if boundary.dependency_name(d) != "SurfaceDeviceContracts"]
        self.assertTrue(boundary.check_manifest(value))

    def test_binding_cannot_point_forward_to_feedback(self):
        value = self.modified()
        next(t for t in value["targets"] if t["name"] == "SurfaceBindingContext")["dependencies"].append({"byName": ["SurfaceFeedbackPlanning", None]})
        self.assertTrue(boundary.check_manifest(value))

    def test_connection_cannot_form_a_cycle_with_feedback(self):
        value = self.modified()
        next(t for t in value["targets"] if t["name"] == "SurfaceConnectionState")["dependencies"].append({"byName": ["SurfaceFeedbackPlanning", None]})
        self.assertTrue(boundary.check_manifest(value))

    def test_evaluated_manifest_order_is_irrelevant(self):
        value = self.modified()
        value["targets"].reverse()
        self.assertEqual(boundary.check_manifest(value), [])

    def test_external_dependency_is_rejected(self):
        value = self.modified()
        value["dependencies"] = [{"sourceControl": [{"identity": "surfaceplugins"}]}]
        self.assertTrue(boundary.check_manifest(value))

    def test_reverse_dependency_is_rejected(self):
        value = self.modified()
        next(t for t in value["targets"] if t["name"] == "SurfaceDeviceContracts")["dependencies"] = [{"byName": ["SurfaceFeedbackPlanning", None]}]
        self.assertTrue(boundary.check_manifest(value))

    def test_conformance_cannot_be_a_production_dependency(self):
        value = self.modified()
        next(t for t in value["targets"] if t["name"] == "SurfaceFeedbackPlanning")["dependencies"].append({"byName": [boundary.CONFORMANCE, None]})
        self.assertTrue(boundary.check_manifest(value))

    def test_external_product_dependency_is_rejected(self):
        value = self.modified()
        value["targets"][0]["dependencies"] = [{"product": ["SurfacePluginContracts", "surfaceplugins", None, None]}]
        self.assertTrue(boundary.check_manifest(value))

    def test_unknown_target_is_rejected(self):
        value = self.modified()
        value["targets"].append({"name": "HiddenDevice", "type": "regular"})
        self.assertTrue(boundary.check_manifest(value))

    def test_test_support_cannot_be_bundled_with_production(self):
        value = self.modified()
        value["products"][0]["targets"].append(boundary.CONFORMANCE)
        self.assertTrue(boundary.check_manifest(value))

    def test_target_cannot_compile_foreign_source_tree(self):
        value = self.modified()
        value["targets"][0]["path"] = "../OtherRepository"
        self.assertTrue(boundary.check_manifest(value))

    def test_unsafe_compiler_overrides_are_rejected(self):
        value = self.modified()
        value["targets"][0]["settings"] = [{"kind": {"unsafeFlags": {"_0": ["-I", "../driver"]}}}]
        self.assertTrue(boundary.check_manifest(value))

    def test_plugin_execution_is_rejected(self):
        value = self.modified()
        value["targets"][0]["pluginUsages"] = [{"plugin": ["Generator", None]}]
        self.assertTrue(boundary.check_manifest(value))


class FeedbackImportBoundaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        root = Path(cls.directory.name)
        cls.sources = {
            "earlier": "import SurfaceDeviceContracts\nimport SurfaceBindingContext\nimport SurfaceConnectionState\n",
            "conformance": "import SurfaceDeviceConformance\n",
            "native": "import CoreMIDI\n",
            "business": "import SurfacePluginContracts\n",
            "feedback": "import SurfaceFeedbackPlanning\n",
        }
        cls.paths = {}
        for name, source in cls.sources.items():
            path = root / (name + ".swift")
            path.write_text(source)
            cls.paths[name] = path
        cls.parsed = boundary.parse_files(list(cls.paths.values()))

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def errors(self, name, target):
        path = self.paths[name]
        return boundary.check_source(path.read_text(), self.parsed[str(path)], target, path.name)

    def test_feedback_may_import_the_three_approved_earlier_targets(self):
        self.assertEqual(self.errors("earlier", "SurfaceFeedbackPlanning"), [])

    def test_feedback_cannot_import_test_support(self):
        self.assertTrue(self.errors("conformance", "SurfaceFeedbackPlanning"))

    def test_feedback_cannot_import_native_or_business_modules(self):
        for name in ["native", "business"]:
            with self.subTest(module=name):
                self.assertTrue(self.errors(name, "SurfaceFeedbackPlanning"))

    def test_binding_cannot_import_feedback(self):
        self.assertTrue(self.errors("feedback", "SurfaceBindingContext"))

    def test_connection_cannot_import_feedback(self):
        self.assertTrue(self.errors("feedback", "SurfaceConnectionState"))
