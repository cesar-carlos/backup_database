#!/usr/bin/env python3
"""Run and filter coverage reports for Flutter/Dart tests."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


IGNORE_PATTERNS = (
    "/test/",
    ".g.dart",
    ".freezed.dart",
    ".mocks.dart",
    "/generated/",
    "/gen/",
)


def step(message: str) -> None:
    print(f"==> {message}")


def is_ignored(path: str) -> bool:
    normalized = path.replace("\\", "/")
    return any(pattern in normalized for pattern in IGNORE_PATTERNS)


def filter_lcov(input_path: Path, output_path: Path) -> None:
    lines = input_path.read_text(encoding="utf-8").splitlines()
    result: list[str] = []
    current_file: str | None = None
    current_block: list[str] = []

    for line in lines:
        if line.startswith("SF:"):
            if current_block and current_file and not is_ignored(current_file):
                result.extend(current_block)
            current_file = line[3:]
            current_block = [line]
            continue

        if current_block:
            current_block.append(line)
            if line == "end_of_record":
                if current_file and not is_ignored(current_file):
                    result.extend(current_block)
                current_block = []
                current_file = None

    if current_block and current_file and not is_ignored(current_file):
        result.extend(current_block)

    output_path.write_text("\n".join(result) + ("\n" if result else ""), encoding="utf-8")


def lcov_coverage(lcov_path: Path) -> float:
    total = 0
    hit = 0
    for line in lcov_path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("DA:"):
            continue
        parts = line[3:].split(",", 1)
        if len(parts) != 2:
            continue
        total += 1
        try:
            if int(parts[1]) > 0:
                hit += 1
        except ValueError:
            pass
    if total == 0:
        return 0.0
    return round(hit * 100.0 / total, 2)


def run(cmd: list[str]) -> int:
    try:
        return subprocess.run(cmd, check=False).returncode
    except FileNotFoundError as exc:
        print(f"ERROR: {exc}")
        return 127


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dart-mode", action="store_true", help="Use dart coverage:test_with_coverage")
    parser.add_argument("--fail-under", type=int, default=0, help="Fail if coverage is below this value")
    parser.add_argument(
        "--test-targets",
        default="",
        help="Comma-separated list of test files for flutter test --coverage",
    )
    args = parser.parse_args()

    if args.dart_mode:
        step("Running Dart coverage with package:coverage")
        cmd = ["dart", "run", "coverage:test_with_coverage"]
        if args.fail_under > 0:
            cmd.extend(["--fail-under", str(args.fail_under)])
        return run(cmd)

    step("Running Flutter tests with coverage")
    cmd = ["flutter", "test", "--coverage"]
    targets = [target.strip() for target in args.test_targets.split(",") if target.strip()]
    cmd.extend(targets)
    exit_code = run(cmd)
    if exit_code != 0:
        return exit_code

    lcov_path = Path("coverage/lcov.info")
    filtered_lcov_path = Path("coverage/lcov.filtered.info")
    if not lcov_path.exists():
        print(f"ERROR: coverage file not found: {lcov_path}")
        return 1

    step("Filtering generated/test files from lcov")
    filter_lcov(lcov_path, filtered_lcov_path)

    coverage = lcov_coverage(filtered_lcov_path)
    print(f"Line coverage (filtered): {coverage}%")
    print(f"Filtered report: {filtered_lcov_path}")

    if args.fail_under > 0 and coverage < args.fail_under:
        print(f"ERROR: coverage {coverage}% is below threshold {args.fail_under}%.")
        return 1

    step("Coverage completed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
