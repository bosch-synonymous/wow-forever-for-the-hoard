"""Build a reproducible, verified For the Hoard ZIP using only Python's standard library.

Run: python tools/build_release.py
The default destination is scratch/dist. Existing archives/receipts are never replaced.
This packages source; run tests/run_lua.py separately before a release.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import sys
import zipfile


ADDON = "ForTheHoard"
VERSION = re.compile(r"0|[1-9][0-9]*")


class PackageError(ValueError):
    """A source or packaging contract was not satisfied."""


def collect_sources(root: Path) -> tuple[str, dict[str, Path]]:
    root = root.resolve()
    source = root / "src" / ADDON
    toc = source / f"{ADDON}.toc"
    if not toc.is_file() or toc.is_symlink():
        raise PackageError(f"Missing regular TOC: {toc}")
    metadata: dict[str, str] = {}
    declared: list[str] = []
    for line in toc.read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if line.startswith("##"):
            key, separator, value = line[2:].partition(":")
            if not separator or not key.strip() or not value.strip() or key.strip() in metadata:
                raise PackageError(f"Invalid or duplicate TOC metadata: {line}")
            metadata[key.strip()] = value.strip()
        elif line and not line.startswith("#"):
            # The current addon is flat. Deliberately reject unexpected paths or
            # assets until their load/provenance contract is added to this builder.
            if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*\.lua", line):
                raise PackageError(f"Unsupported TOC member: {line}")
            declared.append(line)
    required = {
        "Interface": "16001", "Title": "For the Hoard", "Author": "bosch-synonymous",
        "SavedVariables": "ForTheHoardDB", "SavedVariablesPerCharacter": "ForTheHoardCharacterDB",
        "IconTexture": rf"Interface\AddOns\{ADDON}\Icon.tga",
    }
    for key, expected in required.items():
        if metadata.get(key) != expected:
            raise PackageError(f"TOC {key} must be {expected!r}")
    version = metadata.get("Version", "")
    if len(version.split(".")) != 3 or not all(VERSION.fullmatch(part) for part in version.split(".")):
        raise PackageError("TOC Version must contain three nonnegative version numbers")
    if not declared or declared[0] != "Core.lua" or len({name.casefold() for name in declared}) != len(declared):
        raise PackageError("Core.lua must load first; TOC members must be unique ignoring case")
    expected_files = {f"{ADDON}.toc", "README.md", "Icon.tga", *declared}
    actual_files = list(source.iterdir())
    if {path.name for path in actual_files} != expected_files:
        raise PackageError("Addon source contains missing, unexpected or incorrectly cased files")
    if any(not path.is_file() or path.is_symlink() for path in actual_files):
        raise PackageError("Addon source must contain regular files only")
    if len({path.name.casefold() for path in actual_files}) != len(actual_files):
        raise PackageError("Addon filenames collide ignoring case")
    icon = (source / "Icon.tga").read_bytes()
    icon_header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, 64, 64, 32, 8)
    if icon[:18] != icon_header or len(icon) != 18 + 64 * 64 * 4:
        raise PackageError("Icon.tga must be the 64x64 uncompressed 32-bit BGRA texture with bottom-left origin")
    core = (source / "Core.lua").read_text(encoding="utf-8-sig")
    runtime_versions = re.findall(r'^Addon\.version\s*=\s*"([^"]+)"\s*$', core, flags=re.MULTILINE)
    if runtime_versions != [version]:
        raise PackageError("Core.lua runtime version must match the TOC exactly once")
    readme = (source / "README.md").read_text(encoding="utf-8-sig")
    if not re.search(rf"\bVersion {re.escape(version)}(?=\s|$)", readme):
        raise PackageError("The player README must identify the packaged version")
    members = {f"{ADDON}/{name}": source / name for name in sorted(expected_files)}
    for name in ("LICENSE", "CHANGELOG.md"):
        path = root / name
        if not path.is_file() or path.is_symlink() or not path.read_bytes().strip():
            raise PackageError(f"Missing regular distribution document: {name}")
        members[f"{ADDON}/{name}"] = path
    if "MIT License" not in (root / "LICENSE").read_text(encoding="utf-8"):
        raise PackageError("Distribution license must match the selected MIT license")
    if not re.search(rf"^## {re.escape(version)}(?:[ \t].*)?$", (root / "CHANGELOG.md").read_text(encoding="utf-8"), flags=re.MULTILINE):
        raise PackageError("The changelog must include this version")
    return version, dict(sorted(members.items()))


def build(root: Path, output_dir: Path | None = None) -> tuple[Path, Path]:
    root = root.resolve()
    version, sources = collect_sources(root)
    destination = (output_dir or root / "scratch" / "dist").resolve()
    if destination.is_relative_to((root / "src").resolve()):
        raise PackageError("Release output cannot be written into src")
    archive = destination / f"{ADDON}-{version}.zip"
    receipt_path = destination / f"{ADDON}-{version}-verification.json"
    if archive.exists() or receipt_path.exists():
        raise PackageError("An archive or receipt already exists; choose a fresh output directory")
    data = {name: path.read_bytes() for name, path in sources.items()}
    destination.mkdir(parents=True, exist_ok=True)
    created_archive = created_receipt = False
    try:
        # Exclusive creation, fixed timestamps/order/permissions, and no platform
        # paths make the same input bytes reproducible on the same ZIP toolchain.
        with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as output:
            created_archive = True
            for name, payload in data.items():
                info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = 0o100644 << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                output.writestr(info, payload, compresslevel=9)
        with zipfile.ZipFile(archive) as packaged:
            names = packaged.namelist()
            if names != list(data) or packaged.testzip() is not None:
                raise PackageError("Archive membership or CRC verification failed")
            for name, payload in data.items():
                if packaged.read(name) != payload or sources[name].read_bytes() != payload:
                    raise PackageError(f"Archive/source bytes changed or differ: {name}")
        receipt = {
            "version": version, "interface": 16001,
            "native_validation": "pending; automated checks do not exercise the WoW client",
            "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
            "members": [{"name": name, "bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest()}
                        for name, payload in data.items()],
        }
        with receipt_path.open("x", encoding="utf-8", newline="\n") as output:
            created_receipt = True
            output.write(json.dumps(receipt, indent=2) + "\n")
    except BaseException:
        # Remove only files exclusively created by this invocation; never a
        # pre-existing artifact or directory.
        for created, path in ((created_receipt, receipt_path), (created_archive, archive)):
            if created:
                try:
                    path.unlink()
                except OSError as cleanup_error:
                    print(f"Cleanup could not remove {path}: {cleanup_error}", file=sys.stderr)
        raise
    return archive, receipt_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, help="Fresh destination (default: scratch/dist)")
    options = parser.parse_args()
    try:
        archive, receipt = build(Path(__file__).resolve().parent.parent, options.output_dir)
    except (PackageError, OSError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Package rejected: {error}\n")
    print(f"Verified {archive}\nReceipt: {receipt}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
