import hashlib
import os
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from tools import delivery_support as delivery


class DeliverySupportTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name).resolve()
        self.source = self.root / "source"
        self.stage = self.root / "stage"
        self.source.mkdir()
        self.stage.mkdir()
        (self.source / "pkg").mkdir()
        (self.source / "pkg/z.md").write_bytes(b"markdown\r\n")
        (self.source / "pkg/a.py").write_bytes(bytes(range(256)))
        (self.source / "pkg/é.json").write_bytes(b"{}\n")

    def test_copy_matches_copy2_and_keeps_destination_names(self):
        old = self.root / "old"
        old.mkdir()
        (self.stage / "nested").mkdir()
        (old / "nested").mkdir()
        source = self.source / "pkg/a.py"
        source.chmod(0o751)
        os.utime(source, ns=(1_500_000_000_000_000_000, 1_500_000_001_000_000_000))
        shutil.copy2(source, old / "nested/asset")
        delivery.copy_files(self.source, self.stage, [("pkg/a.py", "nested/asset")])
        self.assertEqual(delivery.inventory(self.stage), delivery.inventory(old))
        actual, expected = (self.stage / "nested/asset").stat(), (old / "nested/asset").stat()
        self.assertEqual((actual.st_mode, actual.st_mtime_ns), (expected.st_mode, expected.st_mtime_ns))

    def test_zip_preserves_order_member_bytes_and_legacy_metadata(self):
        pairs = [("pkg/z.md", "pkg/z.md"), ("pkg/é.json", "pkg/é.json"), ("pkg/a.py", "renamed.py")]
        baseline = self.root / "baseline.zip"
        with zipfile.ZipFile(baseline, "w") as archive:
            for source, member in pairs:
                entry = zipfile.ZipInfo(member, date_time=(1980, 1, 1, 0, 0, 0))
                entry.compress_type = zipfile.ZIP_DEFLATED
                entry.external_attr = 0o644 << 16
                archive.writestr(entry, (self.source / source).read_bytes())
        delivery.write_zip(self.source, self.stage, "new.zip", iter(pairs))
        actual = self.stage / "new.zip"
        self.assertEqual(actual.read_bytes(), baseline.read_bytes())
        with zipfile.ZipFile(actual) as archive:
            self.assertEqual(archive.namelist(), [member for _, member in pairs])
            for source, member in pairs:
                self.assertEqual(archive.read(member), (self.source / source).read_bytes())

    def test_empty_selection_and_inventory_path_order(self):
        delivery.copy_files(self.source, self.stage, [])
        self.assertEqual(delivery.hash_files(self.source, []), {})
        self.assertEqual(delivery.inventory(self.stage), {})
        delivery.write_zip(self.source, self.stage, "empty.zip", [])
        with zipfile.ZipFile(self.stage / "empty.zip") as archive:
            self.assertEqual(archive.namelist(), [])
        (self.stage / "pkg").mkdir()
        pairs = [("pkg/a.py", "pkg/a"), ("pkg/z.md", "pkg-plain")]
        delivery.copy_files(self.source, self.stage, pairs)
        files = delivery.inventory(self.stage)
        self.assertEqual(list(files), ["empty.zip", "pkg/a", "pkg-plain"])
        self.assertEqual(files["pkg/a"], hashlib.sha256((self.source / "pkg/a.py").read_bytes()).hexdigest())
        selected = delivery.hash_files(self.source, ["pkg/z.md", "pkg/a.py", "pkg/z.md"])
        self.assertEqual(list(selected), ["pkg/z.md", "pkg/a.py"])

    def test_reject_unsafe_paths_and_duplicate_destinations(self):
        for name in ("../escape", "pkg/../escape", "//absolute", "/absolute", "C:\\absolute", "pkg//x", "pkg/./x", "x\0y"):
            with self.subTest(name=name):
                with self.assertRaises(ValueError):
                    delivery.copy_files(self.source, self.stage, [("pkg/a.py", name)])
                with self.assertRaises(ValueError):
                    delivery.write_zip(self.source, self.stage, "new.zip", [("pkg/a.py", name)])
        for make, paths in (
            (delivery.copy_files, ["same", "same"]),
            (lambda src, dst, pairs: delivery.write_zip(src, dst, "new.zip", pairs), ["same", "same"]),
        ):
            with self.assertRaises(ValueError):
                make(self.source, self.stage, zip(["pkg/a.py", "pkg/z.md"], paths))
        self.assertEqual(list(self.stage.iterdir()), [])

    def test_reject_symlinks_at_roots_parents_leaves_and_existing_files(self):
        (self.root / "alias").symlink_to(self.source, target_is_directory=True)
        (self.source / "alias").symlink_to(self.source / "pkg", target_is_directory=True)
        (self.source / "file-link").symlink_to(self.source / "pkg/a.py")
        (self.stage / "linked-parent").symlink_to(self.source / "pkg", target_is_directory=True)
        (self.stage / "broken").symlink_to("missing")
        (self.stage / "existing").write_bytes(b"old bytes")
        with self.assertRaises(ValueError):
            delivery.hash_files(self.root / "alias/pkg", ["a.py"])
        with self.assertRaises(ValueError):
            delivery.hash_files(self.source, ["alias/a.py"])
        with self.assertRaises(ValueError):
            delivery.write_zip(self.source, self.stage, "new.zip", [("file-link", "safe")])
        with self.assertRaises(ValueError):
            delivery.copy_files(self.source, self.stage, [("pkg/a.py", "linked-parent/new")])
        for destination in ("existing", "broken"):
            with self.assertRaises(FileExistsError):
                delivery.copy_files(self.source, self.stage, [("pkg/a.py", destination)])
            with self.assertRaises(FileExistsError):
                delivery.write_zip(self.source, self.stage, destination, [])
        self.assertEqual((self.stage / "existing").read_bytes(), b"old bytes")
        self.assertTrue((self.stage / "broken").is_symlink())
        self.assertFalse((self.source / "pkg/new").exists())
        with self.assertRaises(ValueError):
            delivery.inventory(self.stage)

    def test_preflight_and_write_failures_leave_a_retryable_stage(self):
        with self.assertRaises(FileNotFoundError):
            delivery.copy_files(self.source, self.stage, [("pkg/a.py", "first"), ("missing", "second")])
        with self.assertRaises(FileNotFoundError):
            delivery.write_zip(self.source, self.stage, "new.zip", [("missing", "missing")])
        original = shutil.copystat

        def fail_second(source, destination):
            if destination.name == "second":
                raise OSError("injected metadata write failure")
            return original(source, destination)

        with patch.object(delivery.shutil, "copystat", side_effect=fail_second), self.assertRaises(OSError):
            delivery.copy_files(self.source, self.stage, [("pkg/a.py", "first"), ("pkg/z.md", "second")])
        with patch.object(delivery.zipfile.ZipFile, "writestr", side_effect=OSError("injected ZIP write failure")):
            with self.assertRaises(OSError):
                delivery.write_zip(self.source, self.stage, "new.zip", [("pkg/a.py", "a.py")])
        self.assertEqual(list(self.stage.iterdir()), [])
        delivery.copy_files(self.source, self.stage, [("pkg/a.py", "first"), ("pkg/z.md", "second")])
        delivery.write_zip(self.source, self.stage, "new.zip", [("pkg/a.py", "a.py")])
        self.assertEqual(list(delivery.inventory(self.stage)), ["first", "new.zip", "second"])
