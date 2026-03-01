#!/usr/bin/env python3
"""Collect logs and local env data for debugging."""

from __future__ import annotations

import os
import shutil
import sys
from datetime import datetime
from pathlib import Path

from _common import APPDATA_LOG_DIR, Color, command_exists, cprint, divider, ensure_project_root, run_command


def main() -> int:
    ensure_project_root()
    divider("Coletando Logs - Server + Client")

    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    log_dir = Path(f"test_logs_{timestamp}")
    log_dir.mkdir(parents=True, exist_ok=True)
    cprint(f"Diretorio de logs: {log_dir}", Color.CYAN)
    print()

    if APPDATA_LOG_DIR is None:
        cprint("APPDATA nao encontrado; pulando coleta de logs do usuario.", Color.YELLOW)
    elif APPDATA_LOG_DIR.exists():
        cprint(f"OK: diretorio de dados encontrado: {APPDATA_LOG_DIR}", Color.GREEN)
        log_files = list(APPDATA_LOG_DIR.rglob("*.log"))
        if log_files:
            cprint(f"Encontrados {len(log_files)} arquivos de log", Color.CYAN)
            print()
            for file in log_files:
                dest = log_dir / file.name
                try:
                    shutil.copy2(file, dest)
                    cprint(f"OK: copiado {file.name}", Color.GREEN)
                except OSError as exc:
                    cprint(f"ERRO ao copiar {file}: {exc}", Color.RED)
        else:
            cprint("Nenhum arquivo .log encontrado.", Color.YELLOW)
    elif APPDATA_LOG_DIR is not None:
        cprint("Diretorio de dados nao encontrado.", Color.YELLOW)

    print()
    env_info = log_dir / "environment_info.txt"
    with env_info.open("w", encoding="utf-8") as handle:
        handle.write("========================================\n")
        handle.write("Environment Information\n")
        handle.write("========================================\n\n")
        handle.write(f"Timestamp: {timestamp}\n")
        handle.write(f"Machine: {os.environ.get('COMPUTERNAME', 'unknown')}\n")
        handle.write(f"User: {os.environ.get('USERNAME', 'unknown')}\n\n")
        handle.write("========================================\n")
        handle.write("Flutter Version\n")
        handle.write("========================================\n")

    flutter_version = run_command(["flutter", "--version"], capture=True) if command_exists("flutter") else None
    with env_info.open("a", encoding="utf-8") as handle:
        if flutter_version is None:
            handle.write("flutter command not found on PATH\n")
        else:
            if flutter_version.stdout:
                handle.write(flutter_version.stdout)
            if flutter_version.stderr:
                handle.write(flutter_version.stderr)
        handle.write("\n========================================\n")
        handle.write("Python Version\n")
        handle.write("========================================\n")
        handle.write(sys.version + "\n")

    cprint("OK: informacoes de ambiente salvas.", Color.GREEN)
    print()

    config_path = log_dir / "current_config.txt"
    with config_path.open("w", encoding="utf-8") as handle:
        handle.write("========================================\n")
        handle.write("Current .env Configuration\n")
        handle.write("========================================\n")

    env_file = Path(".env")
    if env_file.exists():
        content = env_file.read_text(encoding="utf-8")
        with config_path.open("a", encoding="utf-8") as handle:
            handle.write(content)
        cprint("OK: configuracao atual salva.", Color.GREEN)
    else:
        with config_path.open("a", encoding="utf-8") as handle:
            handle.write("No .env file found\n")
        cprint("Nenhum .env encontrado.", Color.YELLOW)

    print()
    divider("Logs coletados com sucesso")
    cprint(f"Local: {log_dir}\\", Color.WHITE)
    cprint("Arquivos:", Color.WHITE)
    for item in sorted(log_dir.iterdir()):
        cprint(f"  - {item.name}", Color.CYAN)
    print()
    cprint("Use estes logs para debugging.", Color.YELLOW)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
