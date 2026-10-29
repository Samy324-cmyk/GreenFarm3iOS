#!/usr/bin/env python3
"""Verify the preserved original program and generate its Dart method bodies.

No APK is executed. The immutable IR is data parsed from the original DEX;
dex_to_dart translates that data into static Dart source for Flutter's compiler.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
from pathlib import Path
import sys


class OriginalProgramError(Exception):
    pass


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def program_counts(program: dict) -> dict[str, int]:
    classes = program["classes"]
    methods = [method for cls in classes for method in cls["methods"]]
    return {
        "classes": len(classes),
        "available_classes": len(program.get("available_classes", [])),
        "methods": len(methods),
        "code_methods": sum(method["code"] is not None for method in methods),
        "instructions": sum(
            instruction["format"] != "payload"
            for method in methods if method["code"] is not None
            for instruction in method["code"]["instructions"]
        ),
    }


def load_original(project_root: Path) -> tuple[dict, dict]:
    source_root = project_root / "game_source"
    provenance = json.loads((source_root / "provenance.json").read_text(encoding="utf-8"))
    if provenance.get("schema") != 1:
        raise OriginalProgramError("Unsupported original-program provenance schema")
    compressed = (source_root / "program.json.gz").read_bytes()
    if len(compressed) != provenance["compressed_bytes"] or digest(compressed) != provenance["compressed_sha256"]:
        raise OriginalProgramError("Compressed original-program length/SHA-256 mismatch; generation refused")
    # Validate compressed bytes before decompression. The committed provenance
    # is reviewed together with the source; these hashes are integrity checks,
    # not a digital signature or a claim of game completeness.
    raw = gzip.decompress(compressed)
    if len(raw) != provenance["program_bytes"] or digest(raw) != provenance["program_sha256"]:
        raise OriginalProgramError("Uncompressed original-program length/SHA-256 mismatch; generation refused")
    program = json.loads(raw)
    if program.get("apk_sha256") != provenance["source_apk_sha256"]:
        raise OriginalProgramError("Original APK SHA-256 differs between IR and provenance")
    if program_counts(program) != provenance["counts"]:
        raise OriginalProgramError("Original-program class/method/instruction counts differ from provenance")
    return program, provenance


def prepare(project_root: Path, *, verify_only: bool = False) -> dict:
    project_root = project_root.resolve(strict=True)
    program, provenance = load_original(project_root)
    if verify_only:
        return {"verified": True, "generated": False, "counts": provenance["counts"]}
    # Imported only after every original input integrity check has passed.
    from dex_to_dart import generate

    output = project_root / "lib" / "generated"
    if output.is_symlink() or (output.exists() and output.resolve() != output):
        raise OriginalProgramError("Generated-output path must not be a link")
    expected = {f"c{index:04d}.dart" for index in range(provenance["counts"]["classes"])} | {"program.dart", "generation.json"}
    if output.exists():
        unexpected = {path.name for path in output.iterdir()} - expected
        if unexpected:
            raise OriginalProgramError(f"Unexpected files in generated output; review before generation: {sorted(unexpected)}")
    generate(program, output)
    report = json.loads((output / "generation.json").read_text(encoding="utf-8"))
    if (report.get("classes") != provenance["counts"]["classes"]
            or report.get("translated_methods") != provenance["counts"]["code_methods"]
            or report.get("source_apk_sha256") != provenance["source_apk_sha256"]
            or report.get("unsupported_opcodes") != 0):
        raise OriginalProgramError("Generated-source report does not match preserved program")
    if {path.name for path in output.iterdir()} != expected:
        raise OriginalProgramError("Generated-source file inventory is incomplete")
    return {"verified": True, "generated": True, "counts": provenance["counts"], "output": str(output)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--verify-only", action="store_true", help="Check original inputs without rewriting generated Dart")
    args = parser.parse_args()
    try:
        print(json.dumps(prepare(args.project_root, verify_only=args.verify_only)))
        return 0
    except (OriginalProgramError, OSError, ValueError, KeyError, TypeError) as error:
        print(f"Original-program preparation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
