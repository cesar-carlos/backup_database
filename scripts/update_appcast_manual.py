#!/usr/bin/env python3
"""Update appcast.xml manually for a specific release version.

DEPRECATED — usar `scripts/sync_appcast_from_releases.py`.

O parser do runtime (`auto_update_service.dart::parseAppcast`) trata `sha256`
como atributo OBRIGATORIO; itens sem ele sao silenciosamente descartados.
Este script aceita `--sha256` para nao quebrar fluxos legados, mas o caminho
oficial e publicar a release com o sidecar `.sha256` e deixar o workflow
`update-appcast` reconstruir o feed via `sync_appcast_from_releases.py`.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
REPO_RELEASES_URL = "https://github.com/cesar-carlos/backup_database/releases"
_SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")


def _get_channel(root: ET.Element) -> ET.Element:
    channel = root.find("channel")
    if channel is None:
        raise RuntimeError("channel node not found in appcast.xml")
    return channel


def _create_root() -> tuple[ET.Element, ET.Element]:
    root = ET.Element("rss")
    root.set("version", "2.0")
    root.set("xmlns:sparkle", SPARKLE_NS)
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = "Backup Database Updates"
    ET.SubElement(channel, "link").text = REPO_RELEASES_URL
    ET.SubElement(channel, "description").text = "Backup Database updates feed"
    return root, channel


def _remove_existing_version_items(channel: ET.Element, version: str) -> int:
    removed = 0
    for item in list(channel.findall("item")):
        enclosure = item.find("enclosure")
        if enclosure is None:
            continue
        sparkle_version = enclosure.get(f"{{{SPARKLE_NS}}}version") or enclosure.get(
            "sparkle:version",
        )
        if sparkle_version == version:
            channel.remove(item)
            removed += 1
    return removed


def update_appcast(
    version: str,
    asset_url: str,
    asset_size: str,
    sha256: str,
) -> None:
    appcast_file = "appcast.xml"

    if os.path.exists(appcast_file):
        tree = ET.parse(appcast_file)
        root = tree.getroot()
        channel = _get_channel(root)
    else:
        root, channel = _create_root()

    removed = _remove_existing_version_items(channel, version)
    if removed:
        print(f"Removed {removed} existing item(s) for version {version}")

    ET.register_namespace("sparkle", SPARKLE_NS)

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {version}"
    ET.SubElement(item, "pubDate").text = datetime.now(timezone.utc).strftime(
        "%a, %d %b %Y %H:%M:%S +0000",
    )

    desc = ET.SubElement(item, "description")
    desc.text = (
        f"<![CDATA[<h2>New Version {version}</h2>"
        "<p>Automatic update via GitHub Release.</p>]]>"
    )

    enclosure = ET.SubElement(item, "enclosure")
    enclosure.set("url", asset_url)
    enclosure.set(f"{{{SPARKLE_NS}}}version", version)
    enclosure.set(f"{{{SPARKLE_NS}}}os", "windows")
    enclosure.set("length", str(asset_size))
    enclosure.set("type", "application/octet-stream")
    enclosure.set("sha256", sha256.lower())

    channel.insert(0, item)

    out_tree = ET.ElementTree(root)
    ET.indent(out_tree, space="  ")

    with open(appcast_file, "wb") as output:
        output.write(b'<?xml version="1.0" encoding="UTF-8"?>\n')
        out_tree.write(output, encoding="utf-8")

    print(f"OK: appcast.xml updated for version {version}")
    print(f"  URL: {asset_url}")
    print(f"  Size: {asset_size} bytes")
    print(f"  SHA-256: {sha256.lower()}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "DEPRECATED: prefira scripts/sync_appcast_from_releases.py. "
            "Mantido para manutencao emergencial; agora exige --sha256 "
            "porque o runtime descarta itens sem ele."
        ),
    )
    parser.add_argument("version", help="Versao no formato x.y.z")
    parser.add_argument("asset_url", help="URL absoluta do instalador .exe")
    parser.add_argument("asset_size", help="Tamanho em bytes do instalador")
    parser.add_argument(
        "--sha256",
        required=True,
        help="SHA-256 hex (64 chars) do instalador. Obrigatorio.",
    )
    args = parser.parse_args()

    sha256 = args.sha256.strip().lower()
    if not _SHA256_PATTERN.match(sha256):
        print(
            "ERRO: --sha256 deve ser um hex de 64 caracteres (sha256sum).",
            file=sys.stderr,
        )
        return 1

    print(
        "AVISO: script DEPRECATED. Use scripts/sync_appcast_from_releases.py "
        "(via workflow update-appcast) para o fluxo oficial.",
        file=sys.stderr,
    )

    update_appcast(
        version=args.version,
        asset_url=args.asset_url,
        asset_size=args.asset_size,
        sha256=sha256,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
