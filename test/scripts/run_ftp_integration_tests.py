#!/usr/bin/env python3
"""Run FTP integration tests with optional real FTP config from .env."""

from __future__ import annotations

import os
from pathlib import Path

from _common import Color, command_exists, cprint, divider, ensure_project_root, parse_dotenv, run_command


REQUIRED_KEYS = ["FTP_IT_HOST", "FTP_IT_USER", "FTP_IT_PASS", "FTP_IT_REMOTE_PATH"]


def main() -> int:
    ensure_project_root()
    if not command_exists("flutter"):
        cprint("ERRO: comando 'flutter' nao encontrado no PATH.", Color.RED)
        return 1

    env_values = parse_dotenv(Path(".env"))
    process_env = os.environ.copy()
    process_env.update(env_values)

    has_real_config = all(bool(process_env.get(key, "").strip()) for key in REQUIRED_KEYS)
    process_env["RUN_FTP_INTEGRATION"] = "1" if has_real_config else "0"
    process_env["RUN_FTP_REAL_INTEGRATION"] = "1" if has_real_config else "0"

    if has_real_config:
        cprint("Modo FTP real habilitado via .env", Color.GREEN)
    else:
        cprint("FTP_IT_* incompleto no .env; testes reais serao pulados.", Color.YELLOW)

    divider("Testes de Integracao FTP")
    result = run_command(
        ["flutter", "test", "test/integration/ftp_integration_test.dart"],
        capture=True,
        env=process_env,
    )

    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print(result.stderr)

    if result.returncode == 0:
        cprint("PASSED: todos os testes FTP passaram.", Color.GREEN)
        return 0

    cprint("FAILED: testes FTP falharam.", Color.RED)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
