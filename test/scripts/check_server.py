#!/usr/bin/env python3
"""Check if socket server is running on localhost:9527."""

from __future__ import annotations

from _common import Color, cprint, divider, ensure_project_root, is_port_open


def main() -> int:
    ensure_project_root()
    divider("Verificando Socket Server")

    host = "localhost"
    port = 9527
    cprint(f"Testando conexao em {host}:{port}", Color.CYAN)
    print()

    try:
        if is_port_open(host, port, timeout_s=5):
            cprint("OK: server esta rodando e aceitando conexoes.", Color.GREEN)
            print()
            cprint("Detalhes:", Color.WHITE)
            cprint(f"  - Host: {host}", Color.WHITE)
            cprint(f"  - Porta: {port}", Color.WHITE)
            cprint("  - Status: Conectado", Color.WHITE)
            return 0

        cprint("FALHA: timeout ao conectar (5s).", Color.RED)
        cprint("Possiveis causas:", Color.YELLOW)
        cprint("  - Server nao esta rodando", Color.YELLOW)
        cprint(f"  - Firewall bloqueando a porta {port}", Color.YELLOW)
        cprint("  - Server rodando em porta diferente", Color.YELLOW)
        return 1
    except OSError as exc:
        cprint(f"ERRO: {exc}", Color.RED)
        cprint("Verifique se:", Color.YELLOW)
        cprint("  1. O server esta rodando (use start_server.py)", Color.YELLOW)
        cprint("  2. DEBUG_APP_MODE=server no .env", Color.YELLOW)
        cprint("  3. SINGLE_INSTANCE_ENABLED=false no .env", Color.YELLOW)
        return 1
    finally:
        print()
        cprint("=" * 42, Color.WHITE)


if __name__ == "__main__":
    raise SystemExit(main())
