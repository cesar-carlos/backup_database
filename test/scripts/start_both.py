#!/usr/bin/env python3
"""Start server and client instances for local integration testing."""

from __future__ import annotations

import subprocess
import time
from pathlib import Path

from _common import Color, command_exists, cprint, divider, ensure_project_root, read_text, run_command


def stop_pid(pid: int) -> None:
    subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], check=False, capture_output=True, text=True)


def restore_env() -> None:
    backup = Path(".env.backup")
    if backup.exists():
        Path(".env").write_text(backup.read_text(encoding="utf-8"), encoding="utf-8")
        backup.unlink(missing_ok=True)
        cprint("Configuracao original restaurada.", Color.YELLOW)


def main() -> int:
    ensure_project_root()
    divider("Backup Database - Server + Client")

    if not command_exists("flutter"):
        cprint("ERRO: comando 'flutter' nao encontrado no PATH.", Color.RED)
        return 1

    if not Path(".env.server").exists() or not Path(".env.client").exists():
        cprint("ERRO: .env.server e .env.client sao obrigatorios.", Color.RED)
        return 1

    if Path(".env").exists():
        Path(".env.backup").write_text(read_text(Path(".env")), encoding="utf-8")
        cprint("Backup do .env atual criado: .env.backup", Color.YELLOW)
        print()

    cprint("Passo 1: Iniciando SERVIDOR...", Color.GREEN)
    print()
    Path(".env").write_text(read_text(Path(".env.server")), encoding="utf-8")

    creationflags = getattr(subprocess, "CREATE_NEW_CONSOLE", 0)
    server_process = subprocess.Popen(
        ["flutter", "run", "-d", "windows"],
        creationflags=creationflags,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        text=True,
    )

    cprint(f"OK: servidor iniciado (PID: {server_process.pid})", Color.GREEN)
    cprint("Aguardando 10 segundos para inicializar...", Color.YELLOW)
    time.sleep(10)
    print()

    cprint("Passo 2: Iniciando CLIENTE...", Color.CYAN)
    print()
    Path(".env").write_text(read_text(Path(".env.client")), encoding="utf-8")
    cprint("Cliente iniciando...", Color.CYAN)
    cprint("=" * 42, Color.GREEN)
    cprint("Ambas as instancias estao rodando!", Color.GREEN)
    cprint("=" * 42, Color.GREEN)
    print()
    cprint("SERVIDOR:", Color.WHITE)
    cprint("  - Modo: Server", Color.WHITE)
    cprint("  - Porta: 9527", Color.WHITE)
    cprint(f"  - PID: {server_process.pid}", Color.WHITE)
    print()
    cprint("CLIENTE:", Color.WHITE)
    cprint("  - Modo: Client", Color.WHITE)
    cprint("  - Conecte em: localhost:9527", Color.WHITE)
    print()
    cprint("Pressione Ctrl+C no cliente para parar ambos.", Color.YELLOW)
    print()

    Path(".server.pid").write_text(str(server_process.pid), encoding="ascii")

    try:
        result = run_command(["flutter", "run", "-d", "windows"])
        return result.returncode
    finally:
        print()
        cprint("Parando servidor...", Color.YELLOW)
        if Path(".server.pid").exists():
            pid_text = Path(".server.pid").read_text(encoding="ascii").strip()
            if pid_text.isdigit():
                stop_pid(int(pid_text))
            Path(".server.pid").unlink(missing_ok=True)
            cprint("OK: servidor parado.", Color.GREEN)
        restore_env()


if __name__ == "__main__":
    raise SystemExit(main())
