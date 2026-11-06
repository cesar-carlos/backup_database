"""Offline tests for the pinned WinSW packaging dependency."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("build_installer", ROOT / "installer/build_installer.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)
HASH = "05b82d46ad331cc16bdc00de5c6332c1ef818df8ceefcd49c726553209b3a0da"


class WinSWBuildTests(unittest.TestCase):
    def test_cached_binary_is_verified(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "dependencies/winsw-2.12.0/BackupDatabaseService.exe"
            target.parent.mkdir(parents=True)
            target.write_bytes(b"existing")
            with patch.object(build.wiu, "sha256_file", return_value=HASH), patch.object(build.urllib.request, "urlretrieve") as download:
                self.assertTrue(build.ensure_winsw_exe(root))
                download.assert_not_called()

    def test_corrupt_download_does_not_replace_existing_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "dependencies/winsw-2.12.0/BackupDatabaseService.exe"
            target.parent.mkdir(parents=True)
            target.write_bytes(b"existing")
            with patch.object(build.wiu, "sha256_file", return_value="bad"), patch.object(build.urllib.request, "urlretrieve", side_effect=lambda url, path: Path(path).write_bytes(b"corrupt")):
                self.assertFalse(build.ensure_winsw_exe(root))
                self.assertEqual(target.read_bytes(), b"existing")
                self.assertFalse(target.with_suffix(".download").exists())

    def test_corrupt_cache_is_replaced_only_after_verification(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "dependencies/winsw-2.12.0/BackupDatabaseService.exe"
            target.parent.mkdir(parents=True)
            target.write_bytes(b"corrupt")
            with patch.object(build.wiu, "sha256_file", side_effect=["bad", HASH]), patch.object(build.urllib.request, "urlretrieve", side_effect=lambda url, path: Path(path).write_bytes(b"verified")):
                self.assertTrue(build.ensure_winsw_exe(root))
                self.assertEqual(target.read_bytes(), b"verified")


if __name__ == "__main__":
    unittest.main()
