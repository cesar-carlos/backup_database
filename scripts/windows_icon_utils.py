"""Shared helpers for Windows icon artifacts.

Single source of truth for hashing, sidecar I/O and exe-embedding checks
used by both `scripts/verify_windows_icons.py` and
`installer/build_installer.py`. Keeping the logic here avoids drift
between the CI validator and the local build pipeline.
"""

from __future__ import annotations

import hashlib
import struct
from pathlib import Path


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
ICO_HEADER_TYPE_ICON = 1
# Quanto do PNG embutido procuramos dentro do .exe. Um prefixo curto
# (cabecalho + IHDR + parte do IDAT) ja e unico o suficiente para ser
# resistente a colisoes e pequeno o bastante para nao caber em outro
# recurso por acidente.
DEFAULT_EXE_PNG_PROBE_BYTES = 200


def sha256_file(path: Path) -> str:
    """Return hex SHA-256 of `path`, reading in 1 MiB chunks."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def icon_source_path(project_root: Path) -> Path:
    return project_root / "assets" / "image" / "new" / "database_512px.png"


def app_icon_path(project_root: Path) -> Path:
    return project_root / "windows" / "runner" / "resources" / "app_icon.ico"


def tray_icon_path(project_root: Path) -> Path:
    return project_root / "assets" / "image" / "new" / "app_tray.ico"


def tray_custom_marker_path(project_root: Path) -> Path:
    return project_root / "assets" / "image" / "new" / ".tray_icon_custom"


def recorded_png_hash_path(project_root: Path) -> Path:
    return project_root / "windows" / "runner" / "resources" / ".app_icon_source_sha256"


def widgetbook_app_icon_path(project_root: Path) -> Path:
    """Sibling Widgetbook catalog reuses the same launcher icon."""
    return (
        project_root
        / "widgetbook"
        / "windows"
        / "runner"
        / "resources"
        / "app_icon.ico"
    )


def release_exe_path(project_root: Path) -> Path:
    return (
        project_root
        / "build"
        / "windows"
        / "x64"
        / "runner"
        / "Release"
        / "backup_database.exe"
    )


def read_recorded_png_hash(project_root: Path) -> str | None:
    path = recorded_png_hash_path(project_root)
    if not path.is_file():
        return None
    return path.read_text(encoding="utf-8").strip()


def write_recorded_png_hash(project_root: Path, icon_source: Path) -> None:
    path = recorded_png_hash_path(project_root)
    path.write_text(f"{sha256_file(icon_source)}\n", encoding="utf-8")


def png_source_hash_mismatch(project_root: Path) -> bool:
    """True when sidecar is missing or diverges from the current PNG."""
    icon_source = icon_source_path(project_root)
    if not icon_source.is_file():
        return False
    recorded = read_recorded_png_hash(project_root)
    if recorded is None:
        return True
    return recorded != sha256_file(icon_source)


def extract_largest_png_from_ico(ico_bytes: bytes) -> bytes | None:
    """Return the largest PNG-encoded image stored inside an .ico file.

    `flutter_launcher_icons` emits ICO files where each entry holds a PNG
    payload (instead of legacy DIB). We return the largest PNG so callers
    can search for it inside the compiled `.exe` resource section.
    """
    if len(ico_bytes) < 6:
        return None
    reserved, image_type, count = struct.unpack("<HHH", ico_bytes[:6])
    if reserved != 0 or image_type != ICO_HEADER_TYPE_ICON or count == 0:
        return None

    entries: list[tuple[int, int]] = []
    cursor = 6
    for _ in range(count):
        if cursor + 16 > len(ico_bytes):
            return None
        size, offset = struct.unpack("<II", ico_bytes[cursor + 8 : cursor + 16])
        entries.append((size, offset))
        cursor += 16

    best: bytes | None = None
    for size, offset in entries:
        if offset + size > len(ico_bytes):
            continue
        payload = ico_bytes[offset : offset + size]
        if not payload.startswith(PNG_SIGNATURE):
            continue
        if best is None or len(payload) > len(best):
            best = payload
    return best


def exe_embeds_icon_png(
    exe_path: Path,
    png_bytes: bytes,
    *,
    probe_bytes: int = DEFAULT_EXE_PNG_PROBE_BYTES,
) -> bool:
    """True when the first `probe_bytes` of `png_bytes` are inside `exe_path`.

    Searching the full PNG would be slower and is unnecessary: the prefix
    is unique because the IHDR/IDAT layout depends on dimensions and the
    source pixels. A 200-byte prefix has astronomically low collision
    probability across unrelated resources in the same `.exe`.
    """
    if not exe_path.is_file() or not png_bytes:
        return False
    needle = png_bytes[: max(1, probe_bytes)]
    with exe_path.open("rb") as handle:
        haystack = handle.read()
    return needle in haystack


def app_icon_png_payload(project_root: Path) -> bytes | None:
    """Convenience: read app_icon.ico from the project and extract its PNG."""
    ico = app_icon_path(project_root)
    if not ico.is_file():
        return None
    return extract_largest_png_from_ico(ico.read_bytes())
