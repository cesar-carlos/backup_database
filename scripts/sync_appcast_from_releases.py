#!/usr/bin/env python3
"""
Script para sincronizar appcast.xml com todos os releases do GitHub.
Busca os releases via API do GitHub e atualiza o appcast.xml.
"""

import xml.etree.ElementTree as ET
from datetime import datetime
import sys
import os
import json
import urllib.request
import urllib.parse

# Namespace do Sparkle
SPARKLE_NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
REPO = 'cesar-carlos/backup_database'

def get_releases():
    """Busca todos os releases do GitHub."""
    url = f'https://api.github.com/repos/{REPO}/releases'
    
    try:
        with urllib.request.urlopen(url) as response:
            data = json.loads(response.read().decode())
            return data
    except Exception as e:
        print(f"ERRO ao buscar releases: {e}")
        return []

def get_exe_asset(release):
    """Encontra o asset .exe em um release."""
    for asset in release.get('assets', []):
        if asset['name'].endswith('.exe'):
            return asset
    return None

def update_appcast():
    """Atualiza o appcast.xml com todos os releases."""
    
    print("Buscando releases do GitHub...")
    releases = get_releases()
    
    if not releases:
        print("ERRO: Nenhum release encontrado")
        sys.exit(1)
    
    print(f"Encontrados {len(releases)} releases")
    
    appcast_file = 'appcast.xml'
    
    # Criar ou carregar appcast.xml
    if os.path.exists(appcast_file):
        tree = ET.parse(appcast_file)
        root = tree.getroot()
        channel = root.find('channel')
        
        if channel is None:
            print(f"ERRO: Canal não encontrado em {appcast_file}")
            sys.exit(1)
        
        # Limpar todos os itens existentes
        for item in list(channel.findall('item')):
            channel.remove(item)
    else:
        # Criar novo appcast.xml
        root = ET.Element('rss')
        root.set('version', '2.0')
        root.set('xmlns:sparkle', SPARKLE_NS)
        channel = ET.SubElement(root, 'channel')
        ET.SubElement(channel, 'title').text = 'Backup Database Updates'
        ET.SubElement(channel, 'link').text = f'https://github.com/{REPO}/releases'
        ET.SubElement(channel, 'description').text = 'Atualizações do Backup Database'
        print(f"Criado novo {appcast_file}")
    
    # Registrar namespace
    ET.register_namespace('sparkle', SPARKLE_NS)
    
    # Processar releases (do mais recente para o mais antigo)
    items_added = 0
    for release in releases:
        if release.get('draft', False) or release.get('prerelease', False):
            print(f"Pulando release {release['tag_name']} (draft ou prerelease)")
            continue
        
        tag_name = release['tag_name']
        # Remover prefixo 'v' se existir
        version = tag_name[1:] if tag_name.startswith('v') else tag_name
        
        # Encontrar asset .exe
        exe_asset = get_exe_asset(release)
        if not exe_asset:
            print(f"AVISO: Nenhum asset .exe encontrado no release {tag_name}")
            continue
        
        asset_url = exe_asset['browser_download_url']
        asset_size = exe_asset['size']
        
        # Criar item
        item = ET.SubElement(channel, 'item')
        ET.SubElement(item, 'title').text = f'Version {version}'
        
        # Usar data de publicação do release
        published_at = release.get('published_at', datetime.utcnow().isoformat())
        try:
            pub_date = datetime.fromisoformat(published_at.replace('Z', '+00:00'))
            pub_date_str = pub_date.strftime('%a, %d %b %Y %H:%M:%S +0000')
        except:
            pub_date_str = datetime.utcnow().strftime('%a, %d %b %Y %H:%M:%S +0000')
        
        ET.SubElement(item, 'pubDate').text = pub_date_str
        
        desc = ET.SubElement(item, 'description')
        body = release.get('body', '') or f'Atualização automática via GitHub Release.'
        desc.text = f'<![CDATA[<h2>Versão {version}</h2><p>{body}</p>]]>'
        
        enclosure = ET.SubElement(item, 'enclosure')
        enclosure.set('url', asset_url)
        enclosure.set(f'{{{SPARKLE_NS}}}version', version)
        enclosure.set(f'{{{SPARKLE_NS}}}os', 'windows')
        enclosure.set('length', str(asset_size))
        enclosure.set('type', 'application/octet-stream')
        
        items_added += 1
        print(f"✓ Adicionado release {tag_name} (versão {version})")
    
    # Ordenar itens por versão (mais recente primeiro)
    items = channel.findall('item')
    items.sort(key=lambda x: x.find('title').text if x.find('title') is not None else '', reverse=True)
    
    # Reorganizar itens no canal
    for item in items:
        channel.remove(item)
        channel.insert(0, item)
    
    # Salvar com formatação
    tree = ET.ElementTree(root)
    ET.indent(tree, space='  ')
    
    # Adicionar declaração XML manualmente
    with open(appcast_file, 'wb') as f:
        f.write(b'<?xml version="1.0" encoding="UTF-8"?>\n')
        tree.write(f, encoding='utf-8', xml_declaration=False)
    
    print(f"\n✓ appcast.xml atualizado com {items_added} releases")
    print(f"  Arquivo salvo: {appcast_file}")

if __name__ == '__main__':
    update_appcast()
































