"""Offline checks for the source-snapshot tool; no GitHub credentials needed."""

import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import repository_manifest as manifest


class RepositoryManifestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.source.mkdir()
        self.destination = self.root / "snapshot"

    def tearDown(self):
        self.temp.cleanup()

    def put(self, name, content=b"content"):
        target = self.source / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)

    def freeze(self):
        result = manifest.snapshot(self.source, self.destination)
        self.manifest_path = self.destination / "manifest.json"
        return result

    def test_includes_originals_generated_code_and_licenses(self):
        for path in ["lib/generated/c0000.dart", "assets/original/0", "third_party/android_json/LICENSE", "third_party/android_json/NOTICE", ".github/workflows/ios.yml"]:
            self.put(path)
        for path in ["build/ios/Runner.app/executable", ".dart_tool/package_config.json", ".git/config", "ios/Pods/Pod", "ios/Flutter/Generated.xcconfig", "tool/__pycache__/helper.pyc"]:
            self.put(path)
        result = self.freeze()
        self.assertEqual(5, result["summary"]["file_count"])
        self.assertEqual(1, result["summary"]["unique_blob_count"])
        self.assertEqual(6, len(result["excluded"]))
        self.assertEqual(result, manifest.verify(self.manifest_path))

    def test_exact_git_blob_hash_and_shell_mode(self):
        self.put("tool/package_ios.sh", b"#!/bin/sh\nexit 0\n")
        self.put("empty", b"")
        entries = {entry["path"]: entry for entry in self.freeze()["files"]}
        self.assertEqual("e69de29bb2d1d6434b8b29ae775ad8c2e48c5391", entries["empty"]["git_blob_sha"])
        script = entries["tool/package_ios.sh"]
        self.assertEqual("100755", script["mode"])
        content = (self.source / script["path"]).read_bytes()
        self.assertEqual(hashlib.sha1(f"blob {len(content)}\0".encode() + content).hexdigest(), script["git_blob_sha"])

    def test_explicit_generated_exclusion_is_preserved_during_verification(self):
        self.put("lib/generated/c0000.dart")
        self.put("game_source/program.json.gz")
        data = manifest.snapshot(self.source, self.destination, exclude_generated=True)
        self.assertEqual(["game_source/program.json.gz"], [entry["path"] for entry in data["files"]])
        output = self.destination / "repository/lib/generated"
        output.mkdir(parents=True)
        (output / "c0000.dart").write_bytes(b"regenerated during validation")
        manifest.verify(self.destination / "manifest.json")

    def test_snapshot_is_separate_and_detects_modified_content(self):
        self.put("lib/a.dart", b"original")
        self.freeze()
        self.put("lib/a.dart", b"later live edit")
        manifest.verify(self.manifest_path)
        frozen = self.destination / "repository/lib/a.dart"
        frozen.write_bytes(b"modified snapshot")
        with self.assertRaisesRegex(manifest.ManifestError, "content or mode changed"):
            manifest.verify(self.manifest_path)

    def test_missing_and_extra_files_fail_even_with_unchanged_manifest(self):
        self.put("a")
        self.freeze()
        frozen = self.destination / "repository"
        (frozen / "a").unlink()
        with self.assertRaisesRegex(manifest.ManifestError, "missing"):
            manifest.verify(self.manifest_path)
        (frozen / "a").write_bytes(b"content")
        (frozen / "unexpected").write_bytes(b"extra")
        with self.assertRaisesRegex(manifest.ManifestError, "extra"):
            manifest.verify(self.manifest_path)

    def test_tampering_with_manifest_fails(self):
        self.put("a")
        data = self.freeze()
        data["files"][0]["size"] += 1
        self.manifest_path.write_text(json.dumps(data), encoding="utf-8")
        with self.assertRaisesRegex(manifest.ManifestError, "digest mismatch"):
            manifest.verify(self.manifest_path)

    def test_unsafe_manifest_path_fails_before_file_access(self):
        self.put("a")
        data = self.freeze()
        data["files"][0]["path"] = "../outside"
        data["files_digest_sha256"] = manifest.canonical_digest(data["files"])
        self.manifest_path.write_text(json.dumps(data), encoding="utf-8")
        with self.assertRaisesRegex(manifest.ManifestError, "Unsafe manifest path"):
            manifest.verify(self.manifest_path)

    def test_plan_deduplicates_and_reuses_remote_sha_regardless_of_path(self):
        self.put("same/a", b"duplicate")
        self.put("same/b", b"duplicate")
        self.put("new", b"new blob")
        data = self.freeze()
        by_path = {entry["path"]: entry for entry in data["files"]}
        remote = self.root / "remote.json"
        remote.write_text(json.dumps({"sha": "remote-tree", "truncated": False, "tree": [
            {"path": "old-location", "sha": by_path["same/a"]["git_blob_sha"], "type": "blob"},
        ]}), encoding="utf-8")
        result = manifest.plan(self.manifest_path, remote)
        self.assertEqual(1, result["summary"]["upload_blob_count"])
        self.assertEqual(1, result["summary"]["reused_blob_count"])
        self.assertEqual(["old-location"], result["summary"]["removed_paths"])
        self.assertEqual(3, len(result["create_tree"]["tree_elements"]))
        self.assertIsNone(result["create_tree"]["base_tree_sha"])

    def test_truncated_remote_tree_fails(self):
        self.put("a")
        self.freeze()
        remote = self.root / "remote.json"
        remote.write_text('{"tree": [], "truncated": true}', encoding="utf-8")
        with self.assertRaisesRegex(manifest.ManifestError, "truncated"):
            manifest.plan(self.manifest_path, remote)

    def test_inline_utf8_batch_preserves_unicode_bom_and_binary_boundaries(self):
        text = "\ufeffá\noriginal\x00text".encode("utf-8")
        self.put("unicode.txt", text)
        self.put("duplicate.txt", text)
        self.put("binary.bin", b"\xff\x80\x00")
        self.freeze()
        result = manifest.plan(self.manifest_path, None, inline_utf8_max_bytes=1024)
        self.assertEqual(1, result["summary"]["inline_blob_count"])
        self.assertEqual(1, result["summary"]["upload_blob_count"])
        batch = result["inline_tree_batches"][0]
        self.assertIsNone(batch["base_tree_sha"])
        self.assertEqual(text, batch["tree_elements"][0]["content"].encode("utf-8"))
        self.assertNotIn("sha", batch["tree_elements"][0])
        self.assertEqual(3, len(result["create_tree"]["tree_elements"]))

    def test_never_overwrites_or_nests_snapshot(self):
        self.put("a")
        with self.assertRaisesRegex(manifest.ManifestError, "outside"):
            manifest.snapshot(self.source, self.source / "snapshot")
        self.freeze()
        with self.assertRaisesRegex(manifest.ManifestError, "already exists"):
            manifest.snapshot(self.source, self.destination)

    def test_private_signing_material_requires_explicit_review(self):
        self.put("ios/distribution.p12")
        with self.assertRaisesRegex(manifest.ManifestError, "private configuration"):
            self.freeze()


if __name__ == "__main__":
    unittest.main()
