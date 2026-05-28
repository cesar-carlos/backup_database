#!/usr/bin/env python3
"""Install repository git hooks under .git/hooks (opt-in).

Hooks live versioned in `scripts/hooks/` and are copied here on demand.
We do NOT use `core.hooksPath` because it would activate the hooks for
every clone silently — opt-in keeps the developer experience explicit.

Usage:
    python scripts/install_git_hooks.py
    python scripts/install_git_hooks.py --force         # overwrite existing
    python scripts/install_git_hooks.py --uninstall     # remove installed hooks
"""

from __future__ import annotations

import argparse
import shutil
import stat
import sys
from pathlib import Path


HOOKS_SOURCE_DIR = Path(__file__).resolve().parent / "hooks"
REPO_ROOT = Path(__file__).resolve().parent.parent
GIT_HOOKS_DIR = REPO_ROOT / ".git" / "hooks"


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--force",
        action="store_true",
        help="Sobrescreve hooks existentes em .git/hooks/",
    )
    parser.add_argument(
        "--uninstall",
        action="store_true",
        help="Remove os hooks instalados anteriormente.",
    )
    return parser.parse_args(argv)


def _iter_source_hooks() -> list[Path]:
    if not HOOKS_SOURCE_DIR.is_dir():
        return []
    return [
        p
        for p in HOOKS_SOURCE_DIR.iterdir()
        if p.is_file() and not p.name.startswith(".")
    ]


def _install(force: bool) -> int:
    if not GIT_HOOKS_DIR.is_dir():
        print(f"ERRO: {GIT_HOOKS_DIR} nao existe (repositorio git valido?)")
        return 1

    sources = _iter_source_hooks()
    if not sources:
        print(f"ERRO: nenhum hook em {HOOKS_SOURCE_DIR}")
        return 1

    for source in sources:
        target = GIT_HOOKS_DIR / source.name
        if target.exists() and not force:
            print(
                f"AVISO: {target} ja existe (use --force para sobrescrever). Pulando."
            )
            continue
        shutil.copy2(source, target)
        # Garante bit de execucao em sistemas POSIX. No Windows, Git for
        # Windows interpreta o shebang via bash.exe que vem no pacote.
        current_mode = target.stat().st_mode
        target.chmod(current_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        print(f"OK: instalado {target}")
    return 0


def _uninstall() -> int:
    sources = _iter_source_hooks()
    if not sources:
        print(f"AVISO: nenhum hook em {HOOKS_SOURCE_DIR} para remover.")
        return 0
    for source in sources:
        target = GIT_HOOKS_DIR / source.name
        if target.exists():
            target.unlink()
            print(f"OK: removido {target}")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    if args.uninstall:
        return _uninstall()
    return _install(force=args.force)


if __name__ == "__main__":
    sys.exit(main())
