#!/usr/bin/env python3
"""Wrapper for scripts/parse_ftp_metrics.dart."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log-path", default="", help="Log file or directory with *.log files")
    parser.add_argument("--export", choices=["csv", "json"], default="", help="Optional export format")
    args = parser.parse_args()

    project_root = Path(__file__).resolve().parents[1]
    command = ["dart", "run", "scripts/parse_ftp_metrics.dart"]

    if args.export:
        command.extend(["--export", args.export])

    if args.log_path:
        target = Path(args.log_path)
        if target.exists() and target.is_dir():
            log_files = sorted(target.glob("*.log"))
            if log_files:
                command.extend(str(path) for path in log_files)
            else:
                command.append(args.log_path)
        else:
            command.append(args.log_path)

    try:
        return subprocess.run(command, cwd=project_root, check=False).returncode
    except FileNotFoundError as exc:
        print(f"ERROR: {exc}")
        return 127


if __name__ == "__main__":
    raise SystemExit(main())
