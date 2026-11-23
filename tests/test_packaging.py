"""Release boundary checks using temporary fixtures under ignored scratch/."""
from pathlib import Path
import hashlib
import io
import json
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import build_release  # noqa: E402


class PackagingTests(unittest.TestCase):
    def setUp(self):
        (ROOT / "scratch").mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix="package-test-", dir=ROOT / "scratch")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "src" / "ForTheHoard"
        shutil.copytree(ROOT / "src" / "ForTheHoard", self.source)
        for name in ("LICENSE", "CHANGELOG.md"):
            shutil.copyfile(ROOT / name, self.root / name)
        self.toc = self.source / "ForTheHoard.toc"
        self.original_toc = self.toc.read_text(encoding="utf-8")

    def change_toc(self, before, after):
        self.assertIn(before, self.original_toc)
        self.toc.write_text(self.original_toc.replace(before, after), encoding="utf-8")

    def rejected(self):
        with self.assertRaises(build_release.PackageError):
            build_release.build(self.root)
        self.assertFalse((self.root / "scratch" / "dist").exists(), "rejected input produced release artifacts")

    def test_real_package_is_installable_exact_and_reproducible(self):
        version, sources = build_release.collect_sources(self.root)
        archive, receipt_path = build_release.build(self.root)
        second, _ = build_release.build(self.root, self.root / "scratch" / "repeat")
        self.assertEqual(archive.name, f"ForTheHoard-{version}.zip")
        self.assertEqual(archive.read_bytes(), second.read_bytes())
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        self.assertEqual(receipt["version"], version)
        self.assertEqual(receipt["archive_sha256"], hashlib.sha256(archive.read_bytes()).hexdigest())
        with zipfile.ZipFile(archive) as packaged:
            self.assertIsNone(packaged.testzip())
            self.assertEqual(packaged.namelist(), sorted(sources))
            self.assertEqual(packaged.namelist(), sorted(f"ForTheHoard/{name}" for name in (
                "Core.lua", "Colors.lua", "Movement.lua", "IndividualBags.lua", "Options.lua",
                "ForTheHoard.toc", "Icon.tga", "README.md", "LICENSE", "CHANGELOG.md",
            )))
            self.assertEqual(len(packaged.namelist()), len(set(name.casefold() for name in packaged.namelist())))
            self.assertIn("ForTheHoard/ForTheHoard.toc", packaged.namelist())
            self.assertIn("ForTheHoard/LICENSE", packaged.namelist())
            self.assertIn("ForTheHoard/CHANGELOG.md", packaged.namelist())
            self.assertEqual(packaged.read("ForTheHoard/Icon.tga"), (self.source / "Icon.tga").read_bytes())
            for item in receipt["members"]:
                name = item["name"]
                self.assertEqual(name.split("/")[0], "ForTheHoard")
                self.assertEqual(len(name.split("/")), 2)
                payload = packaged.read(name)
                self.assertEqual(payload, sources[name].read_bytes())
                self.assertEqual(len(payload), item["bytes"])
                self.assertEqual(hashlib.sha256(payload).hexdigest(), item["sha256"])

    def test_existing_archive_is_preserved(self):
        archive, receipt = build_release.build(self.root)
        original = archive.read_bytes(), receipt.read_bytes()
        with self.assertRaises(build_release.PackageError):
            build_release.build(self.root)
        self.assertEqual((archive.read_bytes(), receipt.read_bytes()), original)

    def test_existing_receipt_alone_is_preserved(self):
        version, _ = build_release.collect_sources(self.root)
        destination = self.root / "scratch" / "dist"
        destination.mkdir(parents=True)
        receipt = destination / f"ForTheHoard-{version}-verification.json"
        receipt.write_bytes(b"previous receipt")
        with self.assertRaises(build_release.PackageError):
            build_release.build(self.root)
        self.assertEqual(receipt.read_bytes(), b"previous receipt")
        self.assertFalse(list(destination.glob("*.zip")))

    def test_cleanup_failure_preserves_primary_build_error(self):
        diagnostic = io.StringIO()
        with patch.object(zipfile.ZipFile, "writestr", side_effect=OSError("primary ZIP failure")), \
                patch.object(Path, "unlink", side_effect=OSError("secondary cleanup failure")), \
                patch("sys.stderr", diagnostic):
            with self.assertRaisesRegex(OSError, "primary ZIP failure"):
                build_release.build(self.root)
        self.assertIn("secondary cleanup failure", diagnostic.getvalue())

    def test_cleanup_attempts_each_owned_artifact(self):
        original_unlink, attempted = Path.unlink, []

        def remove(path, *args, **kwargs):
            attempted.append(path.name)
            if path.suffix == ".json":
                raise OSError("receipt is temporarily locked")
            return original_unlink(path, *args, **kwargs)

        with patch.object(build_release.json, "dumps", side_effect=OSError("primary receipt failure")), \
                patch.object(Path, "unlink", remove), patch("sys.stderr", io.StringIO()):
            with self.assertRaisesRegex(OSError, "primary receipt failure"):
                build_release.build(self.root)
        self.assertEqual(len(attempted), 2)
        self.assertTrue(attempted[0].endswith("-verification.json"))
        self.assertTrue(attempted[1].endswith(".zip"))
        self.assertFalse(list((self.root / "scratch" / "dist").glob("*.zip")))

    def test_output_inside_source_is_rejected(self):
        with self.assertRaises(build_release.PackageError):
            build_release.build(self.root, self.source / "release")
        self.assertFalse((self.source / "release").exists())

    def test_toc_traversal_and_absolute_paths_are_rejected(self):
        for name in ("../Core.lua", "..\\Core.lua", "/Core.lua", "C:/Core.lua", "folder/Core.lua"):
            with self.subTest(name=name):
                self.change_toc("Core.lua", name)
                self.rejected()

    def test_duplicate_and_case_colliding_declarations_are_rejected(self):
        for name in ("Core.lua", "core.lua"):
            with self.subTest(name=name):
                self.toc.write_text(self.original_toc + f"\n{name}\n", encoding="utf-8")
                self.rejected()

    def test_wrong_case_declaration_is_rejected(self):
        self.change_toc("Colors.lua", "colors.lua")
        self.rejected()

    def test_wrong_case_native_toc_is_rejected(self):
        temporary_name = self.toc.with_name("renaming.toc")
        self.toc.rename(temporary_name)
        temporary_name.rename(self.toc.with_name("forthehoard.toc"))
        self.rejected()

    def test_unlisted_file_and_directory_are_rejected(self):
        for name in ("notes.txt", "Unlisted.lua", ".private"):
            with self.subTest(name=name):
                extra = self.source / name
                extra.write_text("must stay out of player ZIP", encoding="utf-8")
                self.rejected()
                extra.unlink()
        (self.source / "working-files").mkdir()
        self.rejected()

    def test_missing_declared_source_is_rejected(self):
        (self.source / "Colors.lua").unlink()
        self.rejected()

    def test_missing_or_wrong_case_icon_is_rejected(self):
        path = self.source / "Icon.tga"
        temporary_name = self.source / "renaming.tga"
        path.rename(temporary_name)
        self.rejected()
        temporary_name.rename(self.source / "icon.tga")
        self.rejected()

    def test_invalid_icon_texture_is_rejected(self):
        path = self.source / "Icon.tga"
        original = path.read_bytes()
        for payload in (b"not a texture", original[:-4], original + b"unexpected trailer",
                        original[:2] + bytes([10]) + original[3:],
                        original[:12] + bytes([63]) + original[13:]):
            with self.subTest(length=len(payload)):
                path.write_bytes(payload)
                self.rejected()

    def test_icon_metadata_must_resolve_to_packaged_asset(self):
        for before, after in (
            (r"Interface\AddOns\ForTheHoard\Icon.tga", r"Interface\AddOns\ForTheHoard\Missing.tga"),
            ("## IconTexture:", "## MissingIconTexture:"),
            (r"Interface\AddOns\ForTheHoard\Icon.tga", r"Interface\AddOns\ForTheHoard\icon.tga"),
        ):
            with self.subTest(after=after):
                self.change_toc(before, after)
                self.rejected()

    def test_version_drift_and_invalid_version_are_rejected(self):
        version, _ = build_release.collect_sources(self.root)
        for value in ("99.0.0", "1.2", "../1", "1.2.3-beta", "1.02.3"):
            with self.subTest(value=value):
                self.change_toc(f"## Version: {version}", f"## Version: {value}")
                self.rejected()

    def test_document_versions_are_checked(self):
        for path in (self.source / "README.md", self.root / "CHANGELOG.md"):
            with self.subTest(path=path.name):
                original = path.read_bytes()
                path.write_text("Version missing", encoding="utf-8")
                self.rejected()
                path.write_bytes(original)

    def test_document_version_prefix_collisions_are_rejected(self):
        version, _ = build_release.collect_sources(self.root)
        for path, marker in ((self.source / "README.md", "Version "), (self.root / "CHANGELOG.md", "## ")):
            with self.subTest(path=path.name):
                original = path.read_text(encoding="utf-8")
                path.write_text(original.replace(marker + version, marker + version + "0"), encoding="utf-8")
                self.rejected()
                path.write_text(original, encoding="utf-8")

    def test_required_documents_are_checked(self):
        for path in (self.source / "README.md", self.root / "LICENSE", self.root / "CHANGELOG.md"):
            with self.subTest(path=path.name):
                original = path.read_bytes()
                path.unlink()
                self.rejected()
                path.write_bytes(original)

    def test_saved_variable_contract_and_client_metadata_are_checked(self):
        for key in ("Interface", "Title", "Author", "SavedVariables", "SavedVariablesPerCharacter"):
            with self.subTest(key=key):
                self.change_toc(f"## {key}:", f"## Wrong{key}:")
                self.rejected()

    def test_duplicate_metadata_is_rejected(self):
        self.toc.write_text(self.original_toc + "\n## Interface: 16001\n", encoding="utf-8")
        self.rejected()

    def test_load_order_is_checked(self):
        self.change_toc("Core.lua\nColors.lua", "Colors.lua\nCore.lua")
        self.rejected()


if __name__ == "__main__":
    unittest.main()
