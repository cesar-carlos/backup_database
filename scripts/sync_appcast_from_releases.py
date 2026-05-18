#!/usr/bin/env python3
"""Rebuild appcast.xml from published GitHub releases."""

from __future__ import annotations

import fnmatch
import hashlib
import json
import os
import sys
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DEFAULT_REPO = "cesar-carlos/backup_database"
DEFAULT_CHANNEL_TITLE = "Backup Database Updates"
DEFAULT_CHANNEL_DESCRIPTION = "Backup Database updates feed"
INSTALLER_PATTERN = "BackupDatabase-Setup-*.exe"


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


def _sha256_from_url(url: str) -> str:
    request = urllib.request.Request(url, headers=_build_headers())
    digest = hashlib.sha256()
    with urllib.request.urlopen(request) as response:
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


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

    return ReleaseAsset(
        name=name,
        url=url,
        size=size,
        sha256=_sha256_from_url(url),
    )


def build_published_releases(repo: str) -> list[PublishedRelease]:
    releases = fetch_releases(repo)
    by_version: dict[str, PublishedRelease] = {}

    for release in releases:
        if release.get("draft") or release.get("prerelease"):
            continue

        tag_name = release.get("tag_name", "")
        version = _normalize_version(tag_name)
        if not version:
            continue

        asset = _select_installer_asset(release)
        published_release = PublishedRelease(
            version=version,
            published_at=release.get("published_at") or "",
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


def render_appcast(repo: str, releases: list[PublishedRelease]) -> ET.ElementTree:
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

    try:
        releases = build_published_releases(repo)
        tree = render_appcast(repo, releases)
        write_appcast(output_path, tree)
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"OK: rebuilt {output_path} with {len(releases)} release item(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
