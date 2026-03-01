#!/usr/bin/env python3
"""Build installer with version sync, dependency checks and ISCC compile."""

from __future__ import annotations

import os
import subprocess
import sys
import urllib.request
from pathlib import Path


VC_REDIST_URL = "https://aka.ms/vs/17/release/vc_redist.x64.exe"


def step(message: str) -> None:
    print(message)


def find_iscc() -> Path | None:
    program_files_x86 = os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")
    program_files = os.environ.get("ProgramFiles", r"C:\Program Files")
    candidates = [
        Path(r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe"),
        Path(r"C:\Program Files\Inno Setup 6\ISCC.exe"),
        Path(program_files_x86) / "Inno Setup 6" / "ISCC.exe",
        Path(program_files) / "Inno Setup 6" / "ISCC.exe",
    ]
    for path in candidates:
        if path.exists():
            return path.resolve()
    return None


def run_command(cmd: list[str], cwd: Path | None = None) -> int:
    try:
        return subprocess.run(cmd, cwd=cwd, check=False).returncode
    except FileNotFoundError as exc:
        print(f"ERRO: {exc}")
        return 127


def main() -> int:
    print("========================================")
    print("  Build do Instalador - Backup Database")
    print("========================================")
    print()

    script_root = Path(__file__).resolve().parent
    project_root = script_root.parent
    update_version_script = script_root / "update_version.py"
    setup_iss_path = script_root / "setup.iss"

    step("Passo 1: Sincronizando versao...")
    if update_version_script.exists():
        code = run_command([sys.executable, str(update_version_script)], cwd=project_root)
        if code != 0:
            print("ERRO: falha ao sincronizar versao")
            return 1
    else:
        print("AVISO: script update_version.py nao encontrado. Pulando sincronizacao.")
    print()

    step("Passo 2: Verificando build do Flutter...")
    exe_path = project_root / "build" / "windows" / "x64" / "runner" / "Release" / "backup_database.exe"
    if not exe_path.exists():
        print(f"ERRO: executavel nao encontrado em: {exe_path}")
        print("Execute primeiro: flutter build windows --release")
        return 1
    print("OK: executavel encontrado")
    print()

    step("Passo 3: Verificando Visual C++ Redistributables...")
    vc_redist_path = script_root / "dependencies" / "vc_redist.x64.exe"
    if not vc_redist_path.exists():
        vc_redist_path.parent.mkdir(parents=True, exist_ok=True)
        print("  Baixando vc_redist.x64.exe...")
        try:
            urllib.request.urlretrieve(VC_REDIST_URL, vc_redist_path)
            print("OK: vc_redist.x64.exe baixado")
        except Exception as exc:  # noqa: BLE001
            print(f"ERRO: falha ao baixar vc_redist.x64.exe: {exc}")
            print(f"Baixe manualmente de: {VC_REDIST_URL}")
            print(f"Salve em: {vc_redist_path}")
            return 1
    else:
        print("OK: vc_redist.x64.exe encontrado")
    print()

    step("Passo 4: Localizando Inno Setup Compiler...")
    iscc_path = find_iscc()
    if iscc_path is None:
        print("ERRO: Inno Setup Compiler nao encontrado.")
        print("Instale o Inno Setup 6 de: https://jrsoftware.org/isdl.php")
        return 1
    print(f"OK: Inno Setup encontrado: {iscc_path}")
    print()

    step("Passo 5: Compilando instalador...")
    print("Aguarde, isso pode levar alguns minutos...")

    code = run_command([str(iscc_path), str(setup_iss_path.resolve())], cwd=script_root)
    if code != 0:
        print("ERRO: falha ao compilar instalador")
        return 1

    print()
    print("========================================")
    print("  Instalador criado com sucesso!")
    print("========================================")

    dist_path = script_root / "dist"
    if dist_path.exists():
        installers = sorted(dist_path.glob("*.exe"), key=lambda p: p.stat().st_mtime, reverse=True)
        if installers:
            latest = installers[0]
            size_mb = round(latest.stat().st_size / (1024 * 1024), 2)
            print()
            print(f"Arquivo: {latest}")
            print(f"Tamanho: {size_mb} MB")
            print()

    print("Proximos passos:")
    print("1. Teste o instalador em uma VM limpa (recomendado)")
    print("2. Faca upload para GitHub Releases")
    print("3. O GitHub Actions atualizara o appcast.xml automaticamente")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
