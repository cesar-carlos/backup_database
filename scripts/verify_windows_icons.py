#!/usr/bin/env python3
"""Verify Windows icon artifacts are present and in sync (CI / pre-release)."""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    png = root / "assets" / "image" / "new" / "database_512px.png"
    app_icon = root / "windows" / "runner" / "resources" / "app_icon.ico"
    tray = root / "assets" / "image" / "new" / "app_tray.ico"
    custom_marker = root / "assets" / "image" / "new" / ".tray_icon_custom"
    source_hash_file = root / "windows" / "runner" / "resources" / ".app_icon_source_sha256"

    errors: list[str] = []

    for path, label in (
        (png, "database_512px.png"),
        (app_icon, "windows/runner/resources/app_icon.ico"),
        (tray, "assets/image/new/app_tray.ico"),
    ):
        if not path.is_file() or path.stat().st_size == 0:
            errors.append(f"missing or empty: {label}")

    if png.is_file() and source_hash_file.is_file():
        recorded = source_hash_file.read_text(encoding="utf-8").strip()
        current = sha256_file(png)
        if recorded != current:
            errors.append(
                "app_icon.ico out of sync with database_512px.png "
                "(run: dart run flutter_launcher_icons or python installer/build_installer.py)",
            )
    elif png.is_file():
        errors.append(
            "missing windows/runner/resources/.app_icon_source_sha256 "
            "(run python installer/build_installer.py once)",
        )

    if (
        not custom_marker.is_file()
        and app_icon.is_file()
        and tray.is_file()
        and sha256_file(app_icon) != sha256_file(tray)
    ):
        errors.append(
            "app_tray.ico differs from app_icon.ico "
            "(run python installer/build_installer.py or add .tray_icon_custom)",
        )

    if errors:
        print("Windows icon verification failed:")
        for message in errors:
            print(f"  - {message}")
        return 1

    print("OK: Windows icon artifacts verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
