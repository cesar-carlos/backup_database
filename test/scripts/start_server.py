#!/usr/bin/env python3
"""Start app in server mode using .env.server."""

from __future__ import annotations

from pathlib import Path

from _common import Color, command_exists, cprint, divider, ensure_project_root, read_text, run_command


def restore_env() -> None:
    backup = Path(".env.backup")
    if backup.exists():
        Path(".env").write_text(backup.read_text(encoding="utf-8"), encoding="utf-8")
        backup.unlink(missing_ok=True)
        cprint("Configuracao original restaurada.", Color.YELLOW)


def main() -> int:
    ensure_project_root()
    divider("Backup Database - Starting SERVER instance")

    if not command_exists("flutter"):
        cprint("ERRO: comando 'flutter' nao encontrado no PATH.", Color.RED)
        return 1

    if not Path(".env.server").exists():
        cprint("ERRO: .env.server nao encontrado.", Color.RED)
        return 1

    if Path(".env").exists():
        Path(".env.backup").write_text(read_text(Path(".env")), encoding="utf-8")
        cprint("Backup do .env atual criado: .env.backup", Color.YELLOW)

    Path(".env").write_text(read_text(Path(".env.server")), encoding="utf-8")
    cprint("Configuracao do servidor carregada (.env.server)", Color.CYAN)
    print()

    env_content = read_text(Path(".env"))
    if "SINGLE_INSTANCE_ENABLED=false" not in env_content:
        cprint("FALHA: SINGLE_INSTANCE_ENABLED deve ser false.", Color.RED)
        restore_env()
        return 1
    cprint("OK: single instance desabilitado.", Color.GREEN)

    if "DEBUG_APP_MODE=server" not in env_content:
        cprint("FALHA: DEBUG_APP_MODE deve ser 'server'.", Color.RED)
        restore_env()
        return 1
    cprint("OK: modo SERVER configurado.", Color.GREEN)
    print()

    divider("Iniciando servidor")
    cprint("Pressione Ctrl+C para parar.", Color.CYAN)
    print()

    try:
        result = run_command(["flutter", "run", "-d", "windows"])
        return result.returncode
    finally:
        restore_env()


if __name__ == "__main__":
    raise SystemExit(main())
