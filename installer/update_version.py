#!/usr/bin/env python3
"""Sync version from pubspec.yaml into installer/setup.iss and .env."""

from __future__ import annotations

import re
import sys
from pathlib import Path


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")


def main() -> int:
    script_root = Path(__file__).resolve().parent
    project_root = script_root.parent

    pubspec_path = project_root / "pubspec.yaml"
    setup_iss_path = script_root / "setup.iss"
    env_path = project_root / ".env"

    print("Sincronizando versao do pubspec.yaml com setup.iss e .env...")

    if not pubspec_path.exists():
        print(f"ERRO: pubspec.yaml nao encontrado em: {pubspec_path}")
        return 1
    if not setup_iss_path.exists():
        print(f"ERRO: setup.iss nao encontrado em: {setup_iss_path}")
        return 1

    pubspec_content = read_text(pubspec_path)
    version_match = re.search(r"(?m)^version:\s*([^\s#]+)", pubspec_content)
    if not version_match:
        print("ERRO: nao foi possivel encontrar a versao no pubspec.yaml")
        return 1

    full_version = version_match.group(1).strip()
    version_only = full_version.split("+", 1)[0]
    print(f"Versao encontrada no pubspec.yaml: {full_version}")
    print(f"Versao (sem build): {version_only}")

    setup_content = read_text(setup_iss_path)
    updated_setup, setup_changes = re.subn(
        r'(?m)^#define\s+MyAppVersion\s+".*"',
        f'#define MyAppVersion "{full_version}"',
        setup_content,
    )
    if setup_changes == 0:
        print("ERRO: nao foi possivel encontrar #define MyAppVersion no setup.iss")
        return 1
    write_text(setup_iss_path, updated_setup)
    print(f"Versao atualizada no setup.iss: {full_version}")

    if env_path.exists():
        env_content = read_text(env_path)
        updated_env, env_changes = re.subn(
            r"(?m)^APP_VERSION\s*=.*$",
            f"APP_VERSION={version_only}",
            env_content,
        )
        if env_changes == 0:
            if updated_env and not updated_env.endswith("\n"):
                updated_env += "\n"
            updated_env += f"APP_VERSION={version_only}\n"
            print("AVISO: APP_VERSION nao encontrado no .env. Adicionando...")
        write_text(env_path, updated_env)
        print(f"Versao atualizada no .env: {version_only}")
    else:
        print("AVISO: arquivo .env nao encontrado. Pulando atualizacao.")

    print()
    print("Sincronizacao concluida com sucesso!")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
