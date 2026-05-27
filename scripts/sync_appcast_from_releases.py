#!/usr/bin/env python3
"""Rebuild appcast.xml from published GitHub releases."""

from __future__ import annotations

import fnmatch
import json
import os
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DEFAULT_REPO = "cesar-carlos/backup_database"
DEFAULT_CHANNEL_TITLE = "Backup Database Updates"
DEFAULT_CHANNEL_DESCRIPTION = "Backup Database updates feed"
DEFAULT_POLICY_PATH = "scripts/appcast_policy.json"
INSTALLER_PATTERN = "BackupDatabase-Setup-*.exe"
CHECKSUM_SUFFIX = ".sha256"


@dataclass(frozen=True)
class ReleaseAsset:
    name: str
    url: str
    size: int
    sha256: str


@dataclass(frozen=True)
class PublishedRelease:
    version: str
    published_at: str
    body: str
    asset: ReleaseAsset


@dataclass(frozen=True)
class AppcastPolicy:
    blocked_versions: frozenset[str]
    min_supported_app_version: str | None
    rollout_percentages: dict[str, int]
    min_publication_age_minutes: dict[str, int]


def _build_api_url(repo: str) -> str:
    return f"https://api.github.com/repos/{repo}/releases"


def _build_repo_releases_link(repo: str) -> str:
    return f"https://github.com/{repo}/releases"


def _build_headers() -> dict[str, str]:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "backup-database-appcast-sync",
    }
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def _get_json(url: str) -> object:
    request = urllib.request.Request(url, headers=_build_headers())
    with urllib.request.urlopen(request) as response:
        return json.loads(response.read().decode("utf-8"))


def fetch_releases(repo: str) -> list[dict]:
    payload = _get_json(_build_api_url(repo))
    if not isinstance(payload, list):
        raise RuntimeError("GitHub API did not return a releases list")
    return payload


def _normalize_version(tag_name: str) -> str:
    return tag_name[1:] if tag_name.startswith("v") else tag_name


def _empty_policy() -> AppcastPolicy:
    return AppcastPolicy(
        blocked_versions=frozenset(),
        min_supported_app_version=None,
        rollout_percentages={},
        min_publication_age_minutes={},
    )


def _parse_blocked(payload: dict, path: Path) -> frozenset[str]:
    raw_versions = payload.get("blocked_versions", [])
    if not isinstance(raw_versions, list):
        raise RuntimeError(
            f"blocked_versions must be a JSON array in appcast policy: {path}"
        )
    versions = {
        _normalize_version(version.strip())
        for version in raw_versions
        if isinstance(version, str) and version.strip()
    }
    return frozenset(versions)


def _parse_min_supported(payload: dict, path: Path) -> str | None:
    raw = payload.get("min_supported_app_version")
    if raw is None:
        return None
    if not isinstance(raw, str) or not raw.strip():
        raise RuntimeError(
            f"min_supported_app_version must be a non-empty string: {path}"
        )
    return _normalize_version(raw.strip())


def _parse_int_map(payload: dict, key: str, path: Path) -> dict[str, int]:
    raw = payload.get(key, {})
    if not isinstance(raw, dict):
        raise RuntimeError(
            f"{key} must be a JSON object {{'<version>': <int>}}: {path}"
        )
    out: dict[str, int] = {}
    for version, value in raw.items():
        if not isinstance(version, str) or not version.strip():
            continue
        if not isinstance(value, int):
            raise RuntimeError(
                f"{key} value for {version} must be integer: {path}"
            )
        out[_normalize_version(version.strip())] = value
    return out


def load_policy(path: Path) -> AppcastPolicy:
    if not path.exists():
        return _empty_policy()

    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise RuntimeError(f"Appcast policy must be a JSON object: {path}")

    return AppcastPolicy(
        blocked_versions=_parse_blocked(payload, path),
        min_supported_app_version=_parse_min_supported(payload, path),
        rollout_percentages=_parse_int_map(
            payload, "rollout_percentages", path,
        ),
        min_publication_age_minutes=_parse_int_map(
            payload, "min_publication_age_minutes", path,
        ),
    )


def _sha256_from_sidecar_content(content: str, installer_name: str) -> str | None:
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line:
            continue

        parts = re.split(r"\s+", line, maxsplit=1)
        if not parts:
            continue

        digest = parts[0].strip().lower()
        if not re.fullmatch(r"[0-9a-f]{64}", digest):
            continue

        if len(parts) == 1:
            return digest

        candidate_name = parts[1].strip().lstrip("*").strip()
        if candidate_name == installer_name:
            return digest

    return None


def _read_checksum_sidecar(asset: dict, installer_name: str) -> str | None:
    url = asset.get("browser_download_url")
    if not isinstance(url, str):
        return None

    request = urllib.request.Request(url, headers=_build_headers())
    with urllib.request.urlopen(request) as response:
        content = response.read().decode("utf-8", errors="replace")
    return _sha256_from_sidecar_content(content, installer_name)


def _select_installer_asset(release: dict) -> ReleaseAsset:
    assets = release.get("assets", [])
    exe_assets = [asset for asset in assets if asset.get("name", "").endswith(".exe")]
    matching_pattern = [
        asset
        for asset in exe_assets
        if fnmatch.fnmatch(asset.get("name", ""), INSTALLER_PATTERN)
    ]

    if len(matching_pattern) == 1:
        selected = matching_pattern[0]
    elif len(matching_pattern) > 1:
        raise RuntimeError(
            f"{release.get('tag_name')}: more than one installer matches {INSTALLER_PATTERN}"
        )
    elif len(exe_assets) == 1:
        selected = exe_assets[0]
    else:
        raise RuntimeError(
            f"{release.get('tag_name')}: expected exactly one .exe installer asset"
        )

    url = selected.get("browser_download_url")
    size = selected.get("size")
    name = selected.get("name")
    if not isinstance(url, str) or not isinstance(name, str) or not isinstance(size, int):
        raise RuntimeError(f"{release.get('tag_name')}: installer asset metadata is invalid")

    checksum_assets = [
        asset
        for asset in assets
        if asset.get("name", "") in {f"{name}{CHECKSUM_SUFFIX}", f"{name}.sha256"}
    ]
    if len(checksum_assets) > 1:
        raise RuntimeError(
            f"{release.get('tag_name')}: more than one checksum sidecar found for {name}"
        )

    if not checksum_assets:
        raise RuntimeError(
            f"{release.get('tag_name')}: missing required checksum sidecar for {name}"
        )

    sha256 = _read_checksum_sidecar(checksum_assets[0], name)
    if sha256 is None:
        raise RuntimeError(
            f"{release.get('tag_name')}: invalid checksum sidecar for {name}"
        )

    return ReleaseAsset(
        name=name,
        url=url,
        size=size,
        sha256=sha256,
    )


def _is_too_young(published_at: str, min_age_minutes: int) -> bool:
    if min_age_minutes <= 0 or not published_at:
        return False
    try:
        parsed = datetime.fromisoformat(published_at.replace("Z", "+00:00"))
    except ValueError:
        return False
    age = datetime.now(timezone.utc) - parsed
    return age.total_seconds() < min_age_minutes * 60


def build_published_releases(repo: str, policy: AppcastPolicy) -> list[PublishedRelease]:
    releases = fetch_releases(repo)
    by_version: dict[str, PublishedRelease] = {}

    for release in releases:
        if release.get("draft") or release.get("prerelease"):
            continue

        tag_name = release.get("tag_name", "")
        version = _normalize_version(tag_name)
        if not version:
            continue
        if version in policy.blocked_versions:
            continue

        published_at_raw = release.get("published_at") or ""
        min_age = policy.min_publication_age_minutes.get(version, 0)
        if _is_too_young(published_at_raw, min_age):
            print(
                f"INFO: holding {version} from appcast (too young; "
                f"min_publication_age_minutes={min_age})",
                file=sys.stderr,
            )
            continue

        asset = _select_installer_asset(release)
        published_release = PublishedRelease(
            version=version,
            published_at=published_at_raw,
            body=(release.get("body") or "").strip(),
            asset=asset,
        )

        existing = by_version.get(version)
        if existing is None or published_release.published_at > existing.published_at:
            by_version[version] = published_release

    ordered = sorted(
        by_version.values(),
        key=lambda item: item.published_at,
        reverse=True,
    )
    if not ordered:
        raise RuntimeError("No published releases with valid installers were found")
    return ordered


def _format_pub_date(published_at: str) -> str:
    parsed = datetime.fromisoformat(published_at.replace("Z", "+00:00"))
    return parsed.strftime("%a, %d %b %Y %H:%M:%S +0000")


def render_appcast(
    repo: str,
    releases: list[PublishedRelease],
    policy: AppcastPolicy,
) -> ET.ElementTree:
    ET.register_namespace("sparkle", SPARKLE_NS)

    root = ET.Element("rss")
    root.set("version", "2.0")

    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = DEFAULT_CHANNEL_TITLE
    ET.SubElement(channel, "link").text = _build_repo_releases_link(repo)
    ET.SubElement(channel, "description").text = DEFAULT_CHANNEL_DESCRIPTION

    for release in releases:
        item = ET.SubElement(channel, "item")
        ET.SubElement(item, "title").text = f"Version {release.version}"
        ET.SubElement(item, "pubDate").text = _format_pub_date(release.published_at)
        ET.SubElement(item, "description").text = (
            release.body or "Automatic update via GitHub Release."
        )

        enclosure = ET.SubElement(item, "enclosure")
        enclosure.set("url", release.asset.url)
        enclosure.set(f"{{{SPARKLE_NS}}}version", release.version)
        enclosure.set(f"{{{SPARKLE_NS}}}os", "windows")
        enclosure.set("length", str(release.asset.size))
        enclosure.set("type", "application/octet-stream")
        enclosure.set("sha256", release.asset.sha256)

        # Atributos opcionais de staged rollout (cliente respeita; sparkle
        # ignora se desconhecer). Mantidos no namespace sparkle para nao
        # poluir o root XML.
        if policy.min_supported_app_version:
            enclosure.set(
                f"{{{SPARKLE_NS}}}minSupportedAppVersion",
                policy.min_supported_app_version,
            )
        rollout = policy.rollout_percentages.get(release.version)
        if rollout is not None:
            clamped = max(0, min(100, rollout))
            enclosure.set(
                f"{{{SPARKLE_NS}}}rolloutPercentage", str(clamped),
            )

    tree = ET.ElementTree(root)
    ET.indent(tree, space="  ")
    return tree


def write_appcast(path: Path, tree: ET.ElementTree) -> None:
    with path.open("wb") as output:
        output.write(b'<?xml version="1.0" encoding="UTF-8"?>\n')
        tree.write(output, encoding="utf-8", xml_declaration=False)


def main() -> int:
    repo = os.environ.get("APPCAST_REPO", DEFAULT_REPO)
    output_path = Path(os.environ.get("APPCAST_OUTPUT", "appcast.xml"))
    policy_path = Path(os.environ.get("APPCAST_POLICY_PATH", DEFAULT_POLICY_PATH))

    try:
        policy = load_policy(policy_path)
        releases = build_published_releases(repo, policy)
        tree = render_appcast(repo, releases, policy)
        write_appcast(output_path, tree)
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(
        f"OK: rebuilt {output_path} with {len(releases)} release item(s) "
        f"(blocked={len(policy.blocked_versions)})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
