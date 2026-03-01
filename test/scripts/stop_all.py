#!/usr/bin/env python3
"""Stop flutter/dart processes used by local integration tests."""

from __future__ import annotations

import csv
import io
import subprocess
from pathlib import Path

from _common import Color, cprint, divider, ensure_project_root, prompt_yes_no


def list_processes() -> list[dict[str, str]]:
    result = subprocess.run(
        ["tasklist", "/v", "/fo", "csv"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return []

    reader = csv.reader(io.StringIO(result.stdout))
    rows: list[dict[str, str]] = []
    next(reader, None)  # header
    for row in reader:
        if len(row) < 2:
            continue
        image = row[0].lower()
        pid = row[1]
        title = row[-1].lower() if row else ""
        if "flutter" in image or "dart" in image or "backup database" in title:
            rows.append({"Image Name": row[0], "PID": pid})
    return rows


def stop_pid(pid: str) -> bool:
    result = subprocess.run(
        ["taskkill", "/PID", pid, "/T", "/F"],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.returncode == 0


def main() -> int:
    ensure_project_root(require_pubspec=False)
    divider("Parando Todas as Instancias")

    processes = list_processes()
    if not processes:
        cprint("Nenhuma instancia rodando.", Color.YELLOW)
        return 0

    cprint(f"Encontradas {len(processes)} instancias:", Color.CYAN)
    print()
    for proc in processes:
        name = proc.get("Image Name", "unknown")
        pid = proc.get("PID", "unknown")
        cprint(f"  - {name} (PID: {pid})", Color.WHITE)

    print()
    if not prompt_yes_no("Deseja parar todas as instancias"):
        cprint("Operacao cancelada.", Color.YELLOW)
        return 0

    print()
    cprint("Parando instancias...", Color.CYAN)
    print()
    stopped = 0
    for proc in processes:
        pid = proc.get("PID", "")
        name = proc.get("Image Name", "unknown")
        if pid and stop_pid(pid):
            cprint(f"OK: parado {name} (PID: {pid})", Color.GREEN)
            stopped += 1
        else:
            cprint(f"ERRO: nao foi possivel parar {name} (PID: {pid})", Color.RED)

    print()
    cprint("=" * 42, Color.GREEN)
    cprint(f"Total de instancias paradas: {stopped}", Color.GREEN)
    cprint("=" * 42, Color.GREEN)
    print()

    cprint("Limpando arquivos temporarios...", Color.CYAN)
    cleaned = 0
    for name in [".env.backup", ".server.pid"]:
        path = Path(name)
        if path.exists():
            path.unlink(missing_ok=True)
            cprint(f"OK: removido {name}", Color.GREEN)
            cleaned += 1

    if cleaned == 0:
        cprint("Nenhum arquivo temporario encontrado.", Color.GRAY)
    else:
        cprint(f"OK: {cleaned} arquivos temporarios removidos.", Color.GREEN)

    print()
    cprint("Limpeza concluida.", Color.GREEN)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
