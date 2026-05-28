#!/usr/bin/env python3
"""Unit tests for `scripts/windows_icon_utils.py`.

Synthetic bytes only — runs on Linux CI without Flutter/Windows artifacts.
Invoke directly (`python test/scripts/test_windows_icon_utils.py`) or via
`python -m unittest test.scripts.test_windows_icon_utils`.
"""

from __future__ import annotations

import struct
import sys
import tempfile
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
SCRIPTS_DIR = PROJECT_ROOT / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import windows_icon_utils as wiu  # noqa: E402


def _png_blob(payload: bytes) -> bytes:
    """Build a PNG with the signature followed by deterministic bytes."""
    return wiu.PNG_SIGNATURE + payload


def _ico_with_pngs(pngs: list[bytes]) -> bytes:
    """Build an ICO file holding `pngs` as entries."""
    header = struct.pack("<HHH", 0, wiu.ICO_HEADER_TYPE_ICON, len(pngs))
    directory_size = 16 * len(pngs)
    first_offset = 6 + directory_size

    directory_chunks: list[bytes] = []
    payload_chunks: list[bytes] = []
    offset = first_offset
    for png in pngs:
        directory_chunks.append(
            struct.pack(
                "<BBBBHHII",
                0,
                0,
                0,
                0,
                1,
                32,
                len(png),
                offset,
            )
        )
        payload_chunks.append(png)
        offset += len(png)
    return header + b"".join(directory_chunks) + b"".join(payload_chunks)


class WindowsIconUtilsTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        (self.root / "assets" / "image" / "new").mkdir(parents=True)
        (self.root / "windows" / "runner" / "resources").mkdir(parents=True)

    def _write_icon_source(self, content: bytes = b"png-source") -> Path:
        path = wiu.icon_source_path(self.root)
        path.write_bytes(content)
        return path

    def test_sha256_file_matches_known_value(self) -> None:
        path = self.root / "sample.bin"
        path.write_bytes(b"hello")
        expected = (
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
        self.assertEqual(wiu.sha256_file(path), expected)

    def test_recorded_hash_round_trip(self) -> None:
        self._write_icon_source(b"version-1")
        self.assertTrue(wiu.png_source_hash_mismatch(self.root))
        wiu.write_recorded_png_hash(self.root, wiu.icon_source_path(self.root))
        self.assertFalse(wiu.png_source_hash_mismatch(self.root))

        # Sidecar drifts when the PNG changes.
        wiu.icon_source_path(self.root).write_bytes(b"version-2")
        self.assertTrue(wiu.png_source_hash_mismatch(self.root))

    def test_png_source_hash_mismatch_is_false_without_source(self) -> None:
        # No PNG, no recorded hash. Nothing to compare → no mismatch.
        self.assertFalse(wiu.png_source_hash_mismatch(self.root))

    def test_extract_largest_png_from_ico_returns_largest(self) -> None:
        small = _png_blob(b"A" * 32)
        large = _png_blob(b"B" * 512)
        ico = _ico_with_pngs([small, large])
        extracted = wiu.extract_largest_png_from_ico(ico)
        self.assertEqual(extracted, large)

    def test_extract_largest_png_from_ico_rejects_non_ico(self) -> None:
        self.assertIsNone(wiu.extract_largest_png_from_ico(b"not an ico"))
        self.assertIsNone(wiu.extract_largest_png_from_ico(b""))

    def test_extract_largest_png_skips_non_png_entries(self) -> None:
        png = _png_blob(b"X" * 64)
        bmp_like = b"\x00\x00\x00\x00" + b"Z" * 60
        ico = _ico_with_pngs([bmp_like, png])
        self.assertEqual(wiu.extract_largest_png_from_ico(ico), png)

    def test_exe_embeds_icon_png_detects_prefix(self) -> None:
        png = _png_blob(b"unique-payload-marker" + b"C" * 256)
        exe_path = self.root / "fake.exe"
        exe_path.write_bytes(b"PE header padding " + png + b"trailing junk")
        self.assertTrue(wiu.exe_embeds_icon_png(exe_path, png))

    def test_exe_embeds_icon_png_false_when_missing(self) -> None:
        png = _png_blob(b"target-bytes" + b"D" * 256)
        exe_path = self.root / "fake.exe"
        exe_path.write_bytes(b"completely unrelated bytes")
        self.assertFalse(wiu.exe_embeds_icon_png(exe_path, png))

    def test_exe_embeds_icon_png_false_when_exe_missing(self) -> None:
        png = _png_blob(b"any")
        self.assertFalse(
            wiu.exe_embeds_icon_png(self.root / "missing.exe", png)
        )

    def test_app_icon_png_payload_round_trip(self) -> None:
        png = _png_blob(b"largest-payload" + b"E" * 400)
        ico_path = wiu.app_icon_path(self.root)
        ico_path.write_bytes(_ico_with_pngs([_png_blob(b"small"), png]))
        self.assertEqual(wiu.app_icon_png_payload(self.root), png)

    def test_app_icon_png_payload_missing_ico_returns_none(self) -> None:
        self.assertIsNone(wiu.app_icon_png_payload(self.root))

    def test_widgetbook_app_icon_path_resolves_to_sibling_catalog(self) -> None:
        path = wiu.widgetbook_app_icon_path(self.root)
        self.assertEqual(
            path,
            self.root
            / "widgetbook"
            / "windows"
            / "runner"
            / "resources"
            / "app_icon.ico",
        )


if __name__ == "__main__":
    unittest.main()
