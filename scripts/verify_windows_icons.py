#!/usr/bin/env python3
"""Verify Windows icon artifacts are present and in sync (CI / pre-release).

Default behaviour stays Linux-friendly (no `.exe` required): the script
checks the PNG source, the generated `.ico`, the tray artifact, the
sibling Widgetbook icon and the sidecar hash. The optional
`--require-exe` flag adds a final check that asserts the PNG embedded in
`windows/runner/resources/app_icon.ico` shows up inside the freshly
built `backup_database.exe` — used by `installer/build_installer.py`
after `flutter build windows --release`.

`--json` emits a machine-parseable summary for workflow integration
(PR comments, Slack, etc.) — the human report is suppressed when this
flag is active.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = PROJECT_ROOT / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import windows_icon_utils as wiu  # noqa: E402


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--require-exe",
        action="store_true",
        help=(
            "Fail when build/windows/.../backup_database.exe is missing or "
            "does not embed the current app_icon.ico payload."
        ),
    )
    group.add_argument(
        "--skip-exe",
        action="store_true",
        help="Skip the .exe check entirely, even when the binary exists.",
    )
    parser.add_argument(
        "--json",
        dest="emit_json",
        action="store_true",
        help=(
            "Emit a JSON report on stdout instead of the human-readable "
            "summary (useful for CI integrations). Exit code is unchanged."
        ),
    )
    return parser.parse_args(argv)


def _collect_errors(args: argparse.Namespace, root: Path) -> list[str]:
    png = wiu.icon_source_path(root)
    app_icon = wiu.app_icon_path(root)
    tray = wiu.tray_icon_path(root)
    custom_marker = wiu.tray_custom_marker_path(root)
    source_hash_file = wiu.recorded_png_hash_path(root)
    widgetbook_icon = wiu.widgetbook_app_icon_path(root)
    exe = wiu.release_exe_path(root)

    errors: list[str] = []

    for path, label in (
        (png, "database_512px.png"),
        (app_icon, "windows/runner/resources/app_icon.ico"),
        (tray, "assets/image/new/app_tray.ico"),
    ):
        if not path.is_file() or path.stat().st_size == 0:
            errors.append(f"missing or empty: {label}")

    if png.is_file() and source_hash_file.is_file():
        if wiu.png_source_hash_mismatch(root):
            errors.append(
                "app_icon.ico out of sync with database_512px.png "
                "(run: dart run flutter_launcher_icons or "
                "python installer/build_installer.py)",
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
        and wiu.sha256_file(app_icon) != wiu.sha256_file(tray)
    ):
        errors.append(
            "app_tray.ico differs from app_icon.ico "
            "(run python installer/build_installer.py or add .tray_icon_custom)",
        )

    # Widgetbook usa o mesmo .ico do app — drift aqui indica que alguem
    # rodou `dart run flutter_launcher_icons` sem o `build_installer.py`,
    # que e quem sincroniza essa copia.
    if widgetbook_icon.parent.is_dir():
        if not widgetbook_icon.is_file():
            errors.append(
                "missing widgetbook/windows/runner/resources/app_icon.ico "
                "(run python installer/build_installer.py to sync)",
            )
        elif (
            app_icon.is_file()
            and wiu.sha256_file(app_icon) != wiu.sha256_file(widgetbook_icon)
        ):
            errors.append(
                "widgetbook app_icon.ico out of sync with primary app_icon.ico "
                "(run python installer/build_installer.py to sync)",
            )

    should_check_exe = not args.skip_exe and (args.require_exe or exe.is_file())
    if should_check_exe:
        if not exe.is_file():
            if args.require_exe:
                errors.append(
                    f"missing build artifact: {exe.relative_to(root)} "
                    "(run flutter build windows --release first)",
                )
        elif app_icon.is_file():
            png_payload = wiu.app_icon_png_payload(root)
            if png_payload is None:
                errors.append(
                    "app_icon.ico has no PNG payload to verify against the .exe "
                    "(regenerate via dart run flutter_launcher_icons)",
                )
            elif not wiu.exe_embeds_icon_png(exe, png_payload):
                errors.append(
                    "backup_database.exe does not embed the current "
                    "app_icon.ico (rebuild via "
                    "python installer/build_installer.py)",
                )

    return errors


def _emit_json(errors: list[str], args: argparse.Namespace) -> None:
    payload = {
        "ok": not errors,
        "errors": errors,
        "require_exe": args.require_exe,
        "skip_exe": args.skip_exe,
    }
    json.dump(payload, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    errors = _collect_errors(args, PROJECT_ROOT)

    if args.emit_json:
        _emit_json(errors, args)
        return 1 if errors else 0

    if errors:
        print("Windows icon verification failed:")
        for message in errors:
            print(f"  - {message}")
        return 1

    print("OK: Windows icon artifacts verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
