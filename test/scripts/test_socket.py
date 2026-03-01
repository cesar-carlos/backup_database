#!/usr/bin/env python3
"""Quick checklist for socket integration tests."""

from __future__ import annotations

from pathlib import Path

from _common import Color, cprint, divider, ensure_project_root, is_port_open, read_text


def main() -> int:
    ensure_project_root()
    divider("Teste de Comunicacao Socket")

    cprint("Passo 1: Verificando servidor...", Color.CYAN)
    if not is_port_open("localhost", 9527, timeout_s=3):
        cprint("FALHA: server nao esta respondendo.", Color.RED)
        cprint("Inicie o servidor com: python test/scripts/start_server.py", Color.YELLOW)
        return 1

    cprint("OK: server esta rodando na porta 9527.", Color.GREEN)
    print()

    cprint("Passo 2: Verificando configuracoes...", Color.CYAN)
    env_path = Path(".env")
    if not env_path.exists():
        cprint("FALHA: arquivo .env nao encontrado.", Color.RED)
        return 1

    env_content = read_text(env_path)
    if "SINGLE_INSTANCE_ENABLED=true" in env_content:
        cprint("FALHA: SINGLE_INSTANCE_ENABLED esta true.", Color.RED)
        cprint("Mude para false para permitir multiplas instancias.", Color.YELLOW)
        cprint("No .env: SINGLE_INSTANCE_ENABLED=false", Color.YELLOW)
        return 1
    cprint("OK: single instance desabilitado.", Color.GREEN)

    if "DEBUG_APP_MODE=server" in env_content:
        mode = "server"
    elif "DEBUG_APP_MODE=client" in env_content:
        mode = "client"
    else:
        cprint("FALHA: DEBUG_APP_MODE nao encontrado no .env.", Color.RED)
        return 1
    cprint(f"OK: modo configurado: {mode}", Color.GREEN)

    print()
    cprint("Passo 3: Testes de integracao disponiveis", Color.CYAN)
    print()
    cprint("Testes automatizados:", Color.WHITE)
    cprint("  1. dart test test/integration/socket_integration_test.dart", Color.WHITE)
    cprint("  2. dart test test/integration/file_transfer_integration_test.dart", Color.WHITE)
    print()
    cprint("Teste manual:", Color.WHITE)
    cprint("  1. Inicie o servidor: python test/scripts/start_server.py", Color.WHITE)
    cprint("  2. Inicie o cliente: python test/scripts/start_client.py", Color.WHITE)
    cprint("  3. No cliente, conecte em localhost:9527", Color.WHITE)
    cprint("  4. Teste: listar agendamentos e transferir arquivos", Color.WHITE)
    print()
    cprint("=" * 42, Color.GREEN)
    cprint("Sistema pronto para testes!", Color.GREEN)
    cprint("=" * 42, Color.GREEN)
    print()
    cprint("Dica: use python test/scripts/check_server.py para validar o server.", Color.YELLOW)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
