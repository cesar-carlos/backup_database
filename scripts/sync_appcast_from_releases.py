#!/usr/bin/env python3
"""Sync appcast.xml with all public GitHub releases."""

from __future__ import annotations

import json
import os
import sys
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
REPO = "cesar-carlos/backup_database"
RELEASES_URL = f"https://api.github.com/repos/{REPO}/releases"
REPO_RELEASES_LINK = f"https://github.com/{REPO}/releases"


def get_releases() -> list[dict]:
    """Fetch releases from GitHub API."""
    request = urllib.request.Request(
        RELEASES_URL,
        headers={"Accept": "application/vnd.github+json", "User-Agent": "backup-database-appcast-sync"},
    )
    try:
        with urllib.request.urlopen(request) as response:
            data = json.loads(response.read().decode("utf-8"))
            if not isinstance(data, list):
                return []
            return data
    except Exception as error:  # pragma: no cover - network failures
        print(f"ERROR: failed to fetch releases: {error}")
        return []


def get_exe_asset(release: dict) -> dict | None:
    """Return .exe asset from a release, if present."""
    for asset in release.get("assets", []):
        if asset.get("name", "").endswith(".exe"):
            return asset
    return None


def create_or_load_appcast(path: str) -> tuple[ET.Element, ET.Element]:
    """Load appcast root/channel or create new structure."""
    if os.path.exists(path):
        tree = ET.parse(path)
        root = tree.getroot()
        channel = root.find("channel")
        if channel is None:
            raise RuntimeError(f"channel not found in {path}")

        for item in list(channel.findall("item")):
            channel.remove(item)
        return root, channel

    root = ET.Element("rss")
    root.set("version", "2.0")
    root.set("xmlns:sparkle", SPARKLE_NS)
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = "Backup Database Updates"
    ET.SubElement(channel, "link").text = REPO_RELEASES_LINK
    ET.SubElement(channel, "description").text = "Backup Database updates feed"
    return root, channel


def format_pub_date(published_at: str | None) -> str:
    """Convert GitHub published_at to RSS pubDate."""
    if not published_at:
        return datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
    try:
        parsed = datetime.fromisoformat(published_at.replace("Z", "+00:00"))
        return parsed.strftime("%a, %d %b %Y %H:%M:%S +0000")
    except ValueError:
        return datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")


def update_appcast() -> int:
    """Rebuild appcast.xml from non-draft and non-prerelease releases."""
    print("Fetching releases from GitHub...")
    releases = get_releases()
    if not releases:
        print("ERROR: no releases found")
        return 1

    appcast_file = "appcast.xml"
    ET.register_namespace("sparkle", SPARKLE_NS)

    try:
        root, channel = create_or_load_appcast(appcast_file)
    except Exception as error:
        print(f"ERROR: unable to load/create appcast: {error}")
        return 1

    items_added = 0
    for release in releases:
        if release.get("draft", False) or release.get("prerelease", False):
            print(f"Skipping {release.get('tag_name', '<unknown>')} (draft/prerelease)")
            continue

        tag_name = release.get("tag_name", "")
        version = tag_name[1:] if tag_name.startswith("v") else tag_name
        if not version:
            continue

        exe_asset = get_exe_asset(release)
        if not exe_asset:
            print(f"WARN: no .exe asset for {tag_name}")
            continue

        asset_url = exe_asset.get("browser_download_url")
        asset_size = exe_asset.get("size")
        if not asset_url or asset_size is None:
            print(f"WARN: invalid asset metadata for {tag_name}")
            continue

        item = ET.SubElement(channel, "item")
        ET.SubElement(item, "title").text = f"Version {version}"
        ET.SubElement(item, "pubDate").text = format_pub_date(release.get("published_at"))

        body = release.get("body") or "Automatic update via GitHub Release."
        desc = ET.SubElement(item, "description")
        desc.text = f"<![CDATA[<h2>Version {version}</h2><p>{body}</p>]]>"

        enclosure = ET.SubElement(item, "enclosure")
        enclosure.set("url", asset_url)
        enclosure.set(f"{{{SPARKLE_NS}}}version", version)
        enclosure.set(f"{{{SPARKLE_NS}}}os", "windows")
        enclosure.set("length", str(asset_size))
        enclosure.set("type", "application/octet-stream")

        items_added += 1
        print(f"OK: added {tag_name} ({version})")

    tree = ET.ElementTree(root)
    ET.indent(tree, space="  ")

    with open(appcast_file, "wb") as output:
        output.write(b'<?xml version="1.0" encoding="UTF-8"?>\n')
        tree.write(output, encoding="utf-8", xml_declaration=False)

    print(f"\nOK: appcast.xml updated with {items_added} release item(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(update_appcast())
