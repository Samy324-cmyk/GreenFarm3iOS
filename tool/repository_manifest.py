#!/usr/bin/env python3
"""Freeze and verify a source snapshot for a later GitHub Git-data upload.

This program never accesses the network, creates commits, or updates refs.
Its manifest is kept outside the repository tree. Run project checks against
the snapshot, then verify again before publishing that exact snapshot.
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import stat
import sys


SCHEMA = 1
MAX_BLOB_BYTES = 100 * 1024 * 1024
EXCLUDED_DIRECTORIES = frozenset({
    ".git", ".dart_tool", ".idea", ".gradle", ".swiftpm", ".symlinks",
    "build", "coverage", "Pods", "ephemeral", "__pycache__", ".pytest_cache",
    "xcuserdata", "DerivedData",
})
EXCLUDED_NAMES = frozenset({
    ".DS_Store", "Thumbs.db", ".flutter-plugins", ".flutter-plugins-dependencies",
    "local.properties", "Generated.xcconfig", "flutter_export_environment.sh",
})
EXCLUDED_SUFFIXES = (".iml", ".class", ".pyc", ".pyo", ".xcuserstate")
PRIVATE_SUFFIXES = (".p12", ".pfx", ".mobileprovision", ".jks", ".keystore")


class ManifestError(Exception):
    pass


def excluded_reason(relative: str, is_directory: bool) -> str | None:
    parts = relative.split("/")
    if any(part in EXCLUDED_DIRECTORIES for part in parts[:-1]):
        return "generated directory"
    name = parts[-1]
    if is_directory and name in EXCLUDED_DIRECTORIES:
        return "generated directory"
    if name in EXCLUDED_NAMES or name.endswith(EXCLUDED_SUFFIXES):
        return "generated or local file"
    return None


def inventory(root: Path, *, exclude_generated: bool = False) -> tuple[list[str], list[dict[str, str]]]:
    files: list[str] = []
    skipped: list[dict[str, str]] = []
    folded: dict[str, str] = {}

    def visit(folder: Path) -> None:
        for child in sorted(folder.iterdir(), key=lambda p: p.name):
            relative = child.relative_to(root).as_posix()
            info = child.lstat()
            # Never follow symbolic links, junctions, or other Windows reparse
            # points, including links whose targets happen to be in the source.
            is_link = stat.S_ISLNK(info.st_mode) or bool(
                getattr(info, "st_file_attributes", 0) & 0x400
            )
            is_dir = stat.S_ISDIR(info.st_mode)
            reason = "reproducible original Dart output" if exclude_generated and relative == "lib/generated" else excluded_reason(relative, is_dir)
            if reason:
                skipped.append({"path": relative, "reason": reason})
                continue
            if is_link:
                raise ManifestError(f"Refusing linked or reparse path: {relative}")
            if "\\" in relative or any(c in relative for c in "\x00\r\n"):
                raise ManifestError(f"Unsafe repository path: {relative!r}")
            previous = folded.setdefault(relative.casefold(), relative)
            if previous != relative:
                raise ManifestError(f"Case-colliding paths: {previous}, {relative}")
            if is_dir:
                visit(child)
            elif stat.S_ISREG(info.st_mode):
                if child.name.endswith(PRIVATE_SUFFIXES) or child.name.startswith(".env"):
                    raise ManifestError(f"Review private configuration before snapshot: {relative}")
                if info.st_size > MAX_BLOB_BYTES:
                    raise ManifestError(f"File exceeds GitHub blob policy: {relative}")
                files.append(relative)
            else:
                raise ManifestError(f"Non-regular source file: {relative}")

    visit(root)
    return sorted(files), skipped


def git_mode(path: Path) -> str:
    # Windows stat commonly reports every file executable. Shell scripts must
    # still retain their executable bit when checked out on the macOS runner.
    executable = path.suffix == ".sh" or (
        os.name != "nt" and bool(path.stat().st_mode & 0o111)
    )
    return "100755" if executable else "100644"


def fingerprint(path: Path, relative: str, *, copy_to: Path | None = None) -> dict:
    before = path.stat()
    content = path.read_bytes()
    after = path.stat()
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise ManifestError(f"Source changed while reading: {relative}")
    if len(content) != before.st_size:
        raise ManifestError(f"Short read: {relative}")
    mode = git_mode(path)
    if copy_to is not None:
        copy_to.parent.mkdir(parents=True, exist_ok=True)
        with copy_to.open("xb") as target:
            target.write(content)
        if os.name != "nt":
            copy_to.chmod(0o755 if mode == "100755" else 0o644)
    header = f"blob {len(content)}\0".encode("ascii")
    return {
        "path": relative,
        "mode": mode,
        "size": len(content),
        "git_blob_sha": hashlib.sha1(header + content).hexdigest(),
        "sha256": hashlib.sha256(content).hexdigest(),
    }


def summarize(entries: list[dict]) -> dict:
    unique = {entry["git_blob_sha"]: entry for entry in entries}
    return {
        "file_count": len(entries),
        "total_bytes": sum(entry["size"] for entry in entries),
        "unique_blob_count": len(unique),
        "unique_blob_bytes": sum(entry["size"] for entry in unique.values()),
        "largest_files": sorted(entries, key=lambda e: (-e["size"], e["path"]))[:10],
    }


def canonical_digest(entries: list[dict]) -> str:
    encoded = json.dumps(entries, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def snapshot(source: Path, destination: Path, *, exclude_generated: bool = False) -> dict:
    source = source.resolve(strict=True)
    destination = destination.resolve()
    if not source.is_dir():
        raise ManifestError("Source must be a directory")
    if destination == source or source in destination.parents:
        raise ManifestError("Snapshot must be outside the live source tree")
    if destination.exists():
        raise ManifestError("Snapshot destination already exists; never overwrite a snapshot")
    paths, excluded = inventory(source, exclude_generated=exclude_generated)
    if not paths:
        raise ManifestError("Source contains no included files")
    destination.mkdir(parents=True)
    repository_root = destination / "repository"
    repository_root.mkdir()
    entries = [fingerprint(source / path, path, copy_to=repository_root / path) for path in paths]
    current_paths, _ = inventory(source, exclude_generated=exclude_generated)
    if paths != current_paths:
        raise ManifestError("Source file inventory changed during snapshot; discard this incomplete candidate")
    for original in entries:
        latest = fingerprint(source / original["path"], original["path"])
        if original != latest:
            raise ManifestError(f"Source changed during snapshot: {original['path']}")
    manifest = {
        "schema": SCHEMA,
        "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "source_root": str(source),
        "repository_root": str(repository_root),
        "review_state": "awaiting_validation_and_publish_authorization",
        "policy": {"exclude_generated": exclude_generated},
        "files_digest_sha256": canonical_digest(entries),
        "summary": summarize(entries),
        "excluded": excluded,
        "files": entries,
    }
    write_json(destination / "manifest.json", manifest)
    return manifest


def read_manifest(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schema") != SCHEMA or not isinstance(data.get("files"), list):
        raise ManifestError("Unknown or invalid manifest format")
    seen = set()
    for entry in data["files"]:
        name = entry.get("path", "")
        parts = name.split("/")
        if not name or "\\" in name or ":" in name or any(p in ("", ".", "..") for p in parts):
            raise ManifestError(f"Unsafe manifest path: {name!r}")
        if name.casefold() in seen:
            raise ManifestError(f"Duplicate or case-colliding manifest path: {name}")
        seen.add(name.casefold())
        if entry.get("mode") not in ("100644", "100755"):
            raise ManifestError(f"Unsupported manifest mode: {name}")
    if canonical_digest(data["files"]) != data.get("files_digest_sha256"):
        raise ManifestError("Manifest file-list digest mismatch")
    if summarize(data["files"]) != data.get("summary"):
        raise ManifestError("Manifest summary mismatch")
    return data


def verify(manifest_path: Path) -> dict:
    data = read_manifest(manifest_path)
    root = Path(data["repository_root"]).resolve(strict=True)
    if root != (manifest_path.resolve().parent / "repository").resolve():
        raise ManifestError("Manifest repository root must be its sibling frozen repository directory")
    paths, _ = inventory(root, exclude_generated=data.get("policy", {}).get("exclude_generated", False))
    expected = [entry["path"] for entry in data["files"]]
    if paths != expected:
        missing = sorted(set(expected) - set(paths))
        extra = sorted(set(paths) - set(expected))
        raise ManifestError(f"Snapshot inventory mismatch; missing={missing}, extra={extra}")
    for expected_entry in data["files"]:
        actual = fingerprint(root / expected_entry["path"], expected_entry["path"])
        if actual != expected_entry:
            raise ManifestError(f"Snapshot content or mode changed: {expected_entry['path']}")
    return data


def plan(manifest_path: Path, remote_tree_path: Path | None, *, inline_utf8_max_bytes: int = 0) -> dict:
    data = verify(manifest_path)
    remote = {"tree": []} if remote_tree_path is None else json.loads(remote_tree_path.read_text(encoding="utf-8"))
    if not isinstance(remote, dict) or not isinstance(remote.get("tree"), list):
        raise ManifestError("Remote tree must be the GitHub recursive-tree JSON object")
    if remote.get("truncated"):
        raise ManifestError("Remote tree is truncated; fetch subtrees before planning")
    available = {entry["sha"] for entry in remote["tree"] if entry.get("type") == "blob"}
    remote_paths = {entry["path"] for entry in remote["tree"] if entry.get("type") != "tree"}
    files_by_sha: dict[str, list[dict]] = collections.defaultdict(list)
    for entry in data["files"]:
        files_by_sha[entry["git_blob_sha"]].append(entry)
    uploads = []
    inline_entries = []
    for sha, entries in sorted(files_by_sha.items()):
        if sha not in available:
            first = entries[0]
            content = None
            if first["size"] <= inline_utf8_max_bytes:
                try:
                    content = (Path(data["repository_root"]) / first["path"]).read_bytes().decode("utf-8")
                except UnicodeError:
                    pass
            if content is not None:
                element = {"path": first["path"], "mode": first["mode"], "type": "blob", "content": content}
                encoded_bytes = len(json.dumps(element, ensure_ascii=False).encode("utf-8"))
                if encoded_bytes < 1000000:
                    inline_entries.append((element, encoded_bytes, first))
                    continue
            uploads.append({
                "sha": sha, "source_path": entries[0]["path"],
                "size": entries[0]["size"], "sha256": entries[0]["sha256"],
                "paths": [entry["path"] for entry in entries],
            })
    tree = [
        {"path": entry["path"], "mode": entry["mode"], "type": "blob", "sha": entry["git_blob_sha"]}
        for entry in data["files"]
    ]
    # Each staging tree is independent and has no base tree. GitHub creates the
    # UTF-8 blobs as part of this request. Their exact SHAs can then be reused by
    # the complete final tree, saving one API mutation per small text file.
    inline_batches = []
    current_batch = {"base_tree_sha": None, "tree_elements": [], "expected_blobs": []}
    batch_bytes = 0
    for element, encoded_bytes, entry in inline_entries:
        if batch_bytes + encoded_bytes > 1000000 and current_batch["tree_elements"]:
            inline_batches.append(current_batch)
            current_batch = {"base_tree_sha": None, "tree_elements": [], "expected_blobs": []}
            batch_bytes = 0
        current_batch["tree_elements"].append(element)
        current_batch["expected_blobs"].append({"path": entry["path"], "sha": entry["git_blob_sha"]})
        batch_bytes += encoded_bytes
    if current_batch["tree_elements"]:
        inline_batches.append(current_batch)
    return {
        "schema": SCHEMA,
        "manifest_digest_sha256": data["files_digest_sha256"],
        "repository_root": data["repository_root"],
        "review_state": data["review_state"],
        "remote_tree_sha": remote.get("sha"),
        "summary": {
            "file_count": len(tree), "upload_blob_count": len(uploads),
            "upload_bytes": sum(entry["size"] for entry in uploads),
            "inline_blob_count": len(inline_entries),
            "inline_tree_count": len(inline_batches),
            "inline_bytes": sum(entry[2]["size"] for entry in inline_entries),
            "reused_blob_count": len(files_by_sha.keys() & available),
            "removed_paths": sorted(remote_paths - {entry["path"] for entry in tree}),
        },
        "uploads": uploads,
        "inline_tree_batches": inline_batches,
        "create_tree": {"base_tree_sha": None, "tree_elements": tree},
    }


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    freeze = commands.add_parser("snapshot", help="Create a new stable copy; source is rechecked after copying")
    freeze.add_argument("--source", type=Path, required=True)
    freeze.add_argument("--destination", type=Path, required=True)
    freeze.add_argument("--exclude-generated", action=argparse.BooleanOptionalAction, default=True,
                        help="Exclude lib/generated; prepare_original.py regenerates it from original IR (default: true)")
    check = commands.add_parser("verify", help="Verify all included paths, bytes, hashes, and modes")
    check.add_argument("--manifest", type=Path, required=True)
    prepare = commands.add_parser("plan", help="Build deduplicated blob-upload and complete-tree arguments")
    prepare.add_argument("--manifest", type=Path, required=True)
    prepare.add_argument("--remote-tree", type=Path)
    prepare.add_argument("--output", type=Path, required=True)
    prepare.add_argument("--inline-utf8-max-bytes", type=int, default=262144,
                         help="Batch UTF-8 blobs up to this size into independent staging-tree requests; zero disables")
    args = parser.parse_args()
    try:
        if args.command == "snapshot":
            result = snapshot(args.source, args.destination, exclude_generated=args.exclude_generated)
        elif args.command == "verify":
            result = verify(args.manifest)
        else:
            if args.inline_utf8_max_bytes < 0:
                raise ManifestError("Inline UTF-8 size limit cannot be negative")
            result = plan(args.manifest, args.remote_tree, inline_utf8_max_bytes=args.inline_utf8_max_bytes)
            write_json(args.output, result)
        print(json.dumps({"ok": True, "command": args.command, "summary": result["summary"]}, ensure_ascii=False))
        return 0
    except (ManifestError, OSError, ValueError, KeyError) as error:
        print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
