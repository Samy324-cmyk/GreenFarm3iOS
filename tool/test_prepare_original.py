"""Failure-case tests for the original-input integrity boundary."""

import gzip
import json
from pathlib import Path
import tempfile
import unittest

import prepare_original as prepare


class PrepareOriginalTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source = self.root / "game_source"
        self.source.mkdir()
        self.program = {
            "apk_sha256": "a" * 64,
            "classes": [{
                "name": "Lfixture/Original;", "super": "Ljava/lang/Object;",
                "access": 1,
                "interfaces": [], "static_fields": [], "instance_fields": [],
                "methods": [],
            }],
        }
        self.raw = json.dumps(self.program, separators=(",", ":")).encode()
        self.compressed = gzip.compress(self.raw, mtime=0)
        self.provenance = {
            "schema": 1,
            "source_apk_sha256": self.program["apk_sha256"],
            "program_sha256": prepare.digest(self.raw),
            "compressed_sha256": prepare.digest(self.compressed),
            "program_bytes": len(self.raw),
            "compressed_bytes": len(self.compressed),
            "counts": prepare.program_counts(self.program),
        }
        (self.source / "program.json.gz").write_bytes(self.compressed)
        self.write_provenance()

    def tearDown(self):
        self.temp.cleanup()

    def write_provenance(self):
        (self.source / "provenance.json").write_text(json.dumps(self.provenance), encoding="utf-8")

    def test_verified_original_generates_expected_files(self):
        result = prepare.prepare(self.root)
        self.assertTrue(result["generated"])
        self.assertEqual({"c0000.dart", "program.dart", "generation.json"},
                         {path.name for path in (self.root / "lib/generated").iterdir()})

    def test_verify_only_leaves_generated_directory_absent(self):
        result = prepare.prepare(self.root, verify_only=True)
        self.assertTrue(result["verified"])
        self.assertFalse(result["generated"])
        self.assertFalse((self.root / "lib").exists())

    def test_corrupt_compressed_data_rejected_before_decompression(self):
        damaged = bytearray(self.compressed)
        damaged[0] ^= 255
        (self.source / "program.json.gz").write_bytes(damaged)
        with self.assertRaisesRegex(prepare.OriginalProgramError, "Compressed original-program"):
            prepare.prepare(self.root)
        self.assertFalse((self.root / "lib").exists())

    def test_raw_hash_mismatch_rejected_before_generation(self):
        self.provenance["program_sha256"] = "0" * 64
        self.write_provenance()
        with self.assertRaisesRegex(prepare.OriginalProgramError, "Uncompressed original-program"):
            prepare.prepare(self.root)

    def test_source_apk_hash_mismatch_rejected(self):
        self.provenance["source_apk_sha256"] = "b" * 64
        self.write_provenance()
        with self.assertRaisesRegex(prepare.OriginalProgramError, "APK SHA-256 differs"):
            prepare.prepare(self.root)

    def test_missing_method_count_rejected(self):
        self.provenance["counts"]["code_methods"] += 1
        self.write_provenance()
        with self.assertRaisesRegex(prepare.OriginalProgramError, "counts differ"):
            prepare.prepare(self.root)

    def test_unexpected_generated_file_is_preserved(self):
        output = self.root / "lib/generated"
        output.mkdir(parents=True)
        handwritten = output / "handwritten.dart"
        handwritten.write_text("keep this", encoding="utf-8")
        with self.assertRaisesRegex(prepare.OriginalProgramError, "Unexpected files"):
            prepare.prepare(self.root)
        self.assertEqual("keep this", handwritten.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
