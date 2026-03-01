#!/usr/bin/env python3
"""Validate .env.server/.env.client files for integration tests."""

from __future__ import annotations

from pathlib import Path

from _common import Color, cprint, divider, ensure_project_root, read_text


def check_file(path: Path, label: str, errors: list[str], warnings: list[str]) -> None:
    if path.exists():
        cprint(f"[OK] {label} encontrado", Color.GREEN)
    else:
        target = errors if label != ".env" else warnings
        prefix = "[ERROR]" if target is errors else "[WARN]"
        color = Color.RED if target is errors else Color.YELLOW
        cprint(f"{prefix} {label} nao encontrado", color)
        target.append(label)


def check_content(path: Path, mode: str, errors: list[str]) -> None:
    if not path.exists():
        return
    content = read_text(path)
    cprint(f"Verificando {path.name}:", Color.CYAN)
    print()

    if "SINGLE_INSTANCE_ENABLED=false" in content:
        cprint("[OK] SINGLE_INSTANCE_ENABLED=false", Color.GREEN)
    else:
        cprint("[ERROR] SINGLE_INSTANCE_ENABLED deve ser false", Color.RED)
        errors.append(f"{path.name}: SINGLE_INSTANCE_ENABLED")

    expected_mode = f"DEBUG_APP_MODE={mode}"
    if expected_mode in content:
        cprint(f"[OK] {expected_mode}", Color.GREEN)
    else:
        cprint(f"[ERROR] DEBUG_APP_MODE deve ser {mode}", Color.RED)
        errors.append(f"{path.name}: DEBUG_APP_MODE")
    print()


def main() -> int:
    ensure_project_root(require_pubspec=False)
    divider("Verificacao de Ambiente")

    errors: list[str] = []
    warnings: list[str] = []

    cprint("Arquivos de configuracao:", Color.CYAN)
    print()

    check_file(Path(".env.server"), ".env.server", errors, warnings)
    check_file(Path(".env.client"), ".env.client", errors, warnings)
    check_file(Path(".env"), ".env", errors, warnings)
    print()

    check_content(Path(".env.server"), "server", errors)
    check_content(Path(".env.client"), "client", errors)

    divider("Resumo")
    if not errors:
        cprint("[OK] Ambiente configurado corretamente!", Color.GREEN)
        print()
        cprint("Proximos passos:", Color.WHITE)
        cprint("  1. python test/scripts/start_server.py (terminal 1)", Color.WHITE)
        cprint("  2. python test/scripts/start_client.py (terminal 2)", Color.WHITE)
        cprint("  3. Ou use: python test/scripts/start_both.py", Color.WHITE)
    else:
        cprint(f"[ERROR] {len(errors)} erros encontrados", Color.RED)
        cprint("[ERROR] Corrija os erros antes de continuar", Color.RED)

    if warnings:
        print()
        cprint(f"[WARN] {len(warnings)} avisos encontrados", Color.YELLOW)

    print()
    cprint("=" * 42, Color.WHITE)
    return len(errors)


if __name__ == "__main__":
    raise SystemExit(main())
