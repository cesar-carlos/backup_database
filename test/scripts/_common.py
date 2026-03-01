#!/usr/bin/env python3
"""Shared helpers for test/dev scripts."""

from __future__ import annotations

import os
import socket
import subprocess
import sys
from pathlib import Path
from typing import Iterable


PROJECT_ROOT = Path(__file__).resolve().parents[2]
APPDATA_ROOT = Path(os.environ["APPDATA"]) if os.environ.get("APPDATA") else None
APPDATA_LOG_DIR = (APPDATA_ROOT / "backup_database") if APPDATA_ROOT else None


class Color:
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    BLUE = "\033[34m"
    CYAN = "\033[36m"
    WHITE = "\033[37m"
    GRAY = "\033[90m"
    RESET = "\033[0m"


def cprint(message: str = "", color: str = Color.WHITE) -> None:
    if sys.stdout.isatty():
        print(f"{color}{message}{Color.RESET}")
    else:
        print(message)


def divider(title: str) -> None:
    cprint("=" * 42, Color.WHITE)
    cprint(title, Color.WHITE)
    cprint("=" * 42, Color.WHITE)
    print()


def ensure_project_root(require_pubspec: bool = True) -> None:
    os.chdir(PROJECT_ROOT)
    if require_pubspec and not Path("pubspec.yaml").exists():
        cprint("ERRO: execute este script na raiz do projeto.", Color.RED)
        raise SystemExit(1)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")


def is_port_open(host: str, port: int, timeout_s: float) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(timeout_s)
        return sock.connect_ex((host, port)) == 0


def run_command(
    cmd: list[str],
    *,
    capture: bool = False,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            cmd,
            check=False,
            text=True,
            capture_output=capture,
            env=env,
        )
    except FileNotFoundError as exc:
        return subprocess.CompletedProcess(
            args=cmd,
            returncode=127,
            stdout="",
            stderr=str(exc),
        )


def parse_dotenv(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if (
            (value.startswith('"') and value.endswith('"'))
            or (value.startswith("'") and value.endswith("'"))
        ) and len(value) >= 2:
            value = value[1:-1]
        if key:
            values[key] = value
    return values


def prompt_yes_no(question: str) -> bool:
    try:
        answer = input(f"{question} (S/N): ").strip().lower()
    except EOFError:
        return False
    return answer in {"s", "sim", "y", "yes"}


def command_exists(name: str) -> bool:
    return subprocess.run(
        ["where", name],
        capture_output=True,
        text=True,
        check=False,
    ).returncode == 0


def print_list(lines: Iterable[str], color: str = Color.WHITE) -> None:
    for line in lines:
        cprint(line, color)
