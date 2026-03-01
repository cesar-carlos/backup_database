#!/usr/bin/env python3
"""Find recent log files under %APPDATA%\\backup_database."""

from __future__ import annotations

import subprocess
from datetime import datetime

from _common import APPDATA_LOG_DIR, Color, cprint, divider


def main() -> int:
    divider("Buscando Logs Recentes")

    if APPDATA_LOG_DIR is None:
        cprint("ERRO: variavel APPDATA nao encontrada no ambiente.", Color.RED)
        return 1

    if not APPDATA_LOG_DIR.exists():
        cprint(f"ERRO: diretorio nao encontrado: {APPDATA_LOG_DIR}", Color.RED)
        return 1

    cprint(f"Diretorio: {APPDATA_LOG_DIR}", Color.CYAN)
    print()

    log_files = sorted(APPDATA_LOG_DIR.rglob("*.log"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not log_files:
        cprint("Nenhum arquivo de log encontrado.", Color.YELLOW)
        print()
        cprint("Possiveis causas:", Color.YELLOW)
        cprint("  1. App ainda nao foi executado", Color.YELLOW)
        cprint("  2. Logs desabilitados", Color.YELLOW)
        cprint("  3. Diretorio de dados diferente", Color.YELLOW)
        return 0

    cprint(f"OK: encontrados {len(log_files)} arquivos.", Color.GREEN)
    print()
    cprint("Logs mais recentes:", Color.CYAN)
    print()

    for log_file in log_files[:5]:
        size_kb = round(log_file.stat().st_size / 1024, 2)
        cprint(log_file.name, Color.WHITE)
        cprint(f"  Path: {log_file.parent}", Color.GRAY)
        cprint(f"  Tamanho: {size_kb} KB", Color.GRAY)
        modified = datetime.fromtimestamp(log_file.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S")
        cprint(f"  Modificado: {modified}", Color.GRAY)
        print()

    try:
        answer = input("Deseja abrir o log mais recente? (S/N): ").strip().lower()
    except EOFError:
        answer = "n"

    if answer in {"s", "sim", "y", "yes"}:
        latest = log_files[0]
        cprint(f"Abrindo: {latest}", Color.CYAN)
        subprocess.run(["notepad", str(latest)], check=False)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
