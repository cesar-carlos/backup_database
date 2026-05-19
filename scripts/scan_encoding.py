#!/usr/bin/env python3
"""Scan repository for common UTF-8 / mojibake encoding issues."""

from __future__ import annotations

import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKIP_DIRS = {
    ".git",
    ".dart_tool",
    "build",
    "node_modules",
    "dist",
    "dependencies",
    "widgetbook/test/goldens",
    "widgetbook/windows/flutter/ephemeral",
    "windows/flutter/ephemeral",
    "__pycache__",
    ".idea",
    ".vscode",
}
SKIP_EXT = {
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".webp",
    ".ico",
    ".exe",
    ".dll",
    ".zip",
    ".so",
    ".dill",
    ".bin",
    ".otf",
    ".ttf",
    ".frag",
    ".dat",
    ".Z",
    ".pdf",
    ".sha256",
    ".lock",
    ".pyc",
    ".exp",
    ".lib",
    ".pdb",
}
SKIP_FILES = {".env", ".env.client", ".env.server", "scan_encoding.py"}

# UTF-8 bytes interpreted as Latin-1/CP1252 (common in PT-BR repos).
MOJIBAKE_PATTERNS: list[tuple[str, str]] = [
    (r"Ã§", "c-cedilla mis-encoded"),
    (r"Ã£", "a-tilde mis-encoded"),
    (r"Ã©", "e-acute mis-encoded"),
    (r"Ã­", "i-acute mis-encoded"),
    (r"Ã³", "o-acute mis-encoded"),
    (r"Ã¡", "a-acute mis-encoded"),
    (r"Ãª", "e-circumflex mis-encoded"),
    (r"Ã´", "o-circumflex mis-encoded"),
    (r"Ãµ", "o-tilde mis-encoded"),
    (r"Ãº", "u-acute mis-encoded"),
    (r"Ã‡", "C-cedilla mis-encoded"),
    (r"Ã‰", "E-acute mis-encoded"),
    (r"â€™", "apostrophe mis-encoded"),
    (r"â€œ", "left double quote mis-encoded"),
    (r"â€\u009d", "right double quote mis-encoded"),
    (r"ï¿½", "U+FFFD literal in source"),
    (r"Ãƒ", "double-encoding hint"),
    (
        r"geraÃ§|configuraÃ§|nÃ£o|versÃ£o|informaÃ§|operaÃ§|validaÃ§|atualizaÃ§|exceÃ§|funÃ§|aÃ§Ã£o",
        "PT word mojibake",
    ),
]


def should_scan(path: Path) -> bool:
    if path.name in SKIP_FILES:
        return False
    if path.suffix.lower() in SKIP_EXT:
        return False
    if SKIP_DIRS & set(path.parts):
        return False
    return True


def scan_file(path: Path) -> list[tuple[str, str]]:
    issues: list[tuple[str, str]] = []
    try:
        raw = path.read_bytes()
    except OSError as exc:
        return [("read_error", str(exc))]

    if raw.startswith(b"\xef\xbb\xbf"):
        issues.append(("utf8_bom", "UTF-8 BOM at start of file"))

    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        issues.append(("invalid_utf8", str(exc)))
        return issues

    lines = text.splitlines()
    if "\ufffd" in text:
        for i, line in enumerate(lines, 1):
            if "\ufffd" in line:
                issues.append(("unicode_replacement", f"line {i}: {line[:120]}"))

    for pattern, desc in MOJIBAKE_PATTERNS:
        for match in re.finditer(pattern, text):
            line_no = text[: match.start()].count("\n") + 1
            snippet = lines[line_no - 1].strip()[:100] if line_no <= len(lines) else ""
            issues.append(("mojibake", f"{desc} line {line_no}: {snippet}"))

    if b"\r\n" in raw:
        lone_lf = raw.replace(b"\r\n", b"").count(b"\n")
        if lone_lf > 0:
            issues.append(("mixed_eol", f"CRLF + {lone_lf} lone LF byte(s)"))

    for i, line in enumerate(lines, 1):
        if re.search(r"[\x80-\x9f]", line):
            issues.append(("c1_control", f"line {i}: {line[:80]}"))

    return issues


def main() -> int:
    all_issues: dict[str, list[tuple[str, str]]] = {}
    scanned = 0

    for path in ROOT.rglob("*"):
        if not path.is_file() or not should_scan(path):
            continue
        scanned += 1
        issues = scan_file(path)
        if issues:
            rel = path.relative_to(ROOT).as_posix()
            all_issues[rel] = issues

    print(f"Scanned {scanned} files under {ROOT}")
    print(f"Issues in {len(all_issues)} file(s)\n")

    for fp in sorted(all_issues):
        print(f"=== {fp} ===")
        for kind, msg in all_issues[fp][:8]:
            print(f"  [{kind}] {msg}")
        extra = len(all_issues[fp]) - 8
        if extra > 0:
            print(f"  ... +{extra} more")
        print()

    counter: Counter[str] = Counter()
    for issues in all_issues.values():
        for kind, _ in issues:
            counter[kind] += 1

    if counter:
        print("Summary:")
        for kind, count in counter.most_common():
            print(f"  {kind}: {count}")
    else:
        print("No encoding issues detected.")

    return 1 if any(k in counter for k in ("invalid_utf8", "mojibake", "unicode_replacement")) else 0


if __name__ == "__main__":
    raise SystemExit(main())
