#!/usr/bin/env python3
"""Run socket integration tests."""

from __future__ import annotations

from _common import Color, command_exists, cprint, divider, ensure_project_root, is_port_open, prompt_yes_no, run_command


TESTS = [
    ("Socket Integration", "test/integration/socket_integration_test.dart"),
    ("File Transfer", "test/integration/file_transfer_integration_test.dart"),
]


def main() -> int:
    ensure_project_root()
    if not command_exists("dart"):
        cprint("ERRO: comando 'dart' nao encontrado no PATH.", Color.RED)
        return 1

    divider("Testes de Integracao - Socket")

    cprint("Passo 1: Verificando se servidor esta rodando...", Color.CYAN)
    if is_port_open("localhost", 9527, timeout_s=2):
        cprint("OK: servidor detectado na porta 9527.", Color.GREEN)
        cprint("AVISO: os testes iniciam o proprio servidor.", Color.YELLOW)
        if not prompt_yes_no("Deseja continuar mesmo assim"):
            cprint("Cancelado pelo usuario.", Color.YELLOW)
            return 0
    else:
        cprint("OK: porta 9527 livre (ok para testes).", Color.GREEN)

    print()
    cprint("Passo 2: Executando testes de integracao...", Color.CYAN)
    print()

    passed = 0
    failed = 0
    for name, path in TESTS:
        cprint("=" * 42, Color.WHITE)
        cprint(f"Testando: {name}", Color.WHITE)
        cprint("=" * 42, Color.WHITE)
        print()
        cprint(f"Comando: dart test {path}", Color.CYAN)
        print()

        result = run_command(["dart", "test", path], capture=True)
        if result.returncode == 0:
            cprint(f"OK: PASSED {name}", Color.GREEN)
            passed += 1
        else:
            cprint(f"FALHA: FAILED {name}", Color.RED)
            if result.stdout:
                print(result.stdout)
            if result.stderr:
                print(result.stderr)
            failed += 1
        print()

    divider("Resumo dos Testes")
    cprint(f"Total: {len(TESTS)}", Color.WHITE)
    cprint(f"Passou: {passed}", Color.GREEN)
    cprint(f"Falhou: {failed}", Color.RED)
    print()

    if failed == 0:
        cprint("OK: todos os testes passaram.", Color.GREEN)
        return 0

    cprint("FALHA: alguns testes falharam.", Color.RED)
    cprint("Revise os erros acima e corrija antes de continuar.", Color.YELLOW)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
