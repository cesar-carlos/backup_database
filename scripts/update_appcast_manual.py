#!/usr/bin/env python3
"""
Script para atualizar manualmente o appcast.xml com releases do GitHub.
Use este script se o workflow do GitHub Actions não executar corretamente.
"""

import xml.etree.ElementTree as ET
from datetime import datetime
import sys
import os

# Namespace do Sparkle
SPARKLE_NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'

def update_appcast(version, asset_url, asset_size):
    """Atualiza o appcast.xml com um novo release."""
    
    appcast_file = 'appcast.xml'
    
    # Criar ou carregar appcast.xml
    if os.path.exists(appcast_file):
        tree = ET.parse(appcast_file)
        root = tree.getroot()
        channel = root.find('channel')
        
        if channel is None:
            print(f"ERRO: Canal não encontrado em {appcast_file}")
            sys.exit(1)
        
        # Remover item existente com a mesma versão (se houver)
        for item in channel.findall('item'):
            enclosure = item.find('enclosure')
            if enclosure is not None:
                sparkle_version = enclosure.get(f'{{{SPARKLE_NS}}}version') or enclosure.get('sparkle:version')
                if sparkle_version == version:
                    channel.remove(item)
                    print(f"Removido item existente com versão {version}")
    else:
        # Criar novo appcast.xml
        root = ET.Element('rss')
        root.set('version', '2.0')
        root.set('xmlns:sparkle', SPARKLE_NS)
        channel = ET.SubElement(root, 'channel')
        ET.SubElement(channel, 'title').text = 'Backup Database Updates'
        ET.SubElement(channel, 'link').text = 'https://github.com/cesar-carlos/backup_database/releases'
        ET.SubElement(channel, 'description').text = 'Atualizações do Backup Database'
        print(f"Criado novo {appcast_file}")
    
    # Registrar namespace
    ET.register_namespace('sparkle', SPARKLE_NS)
    
    # Criar novo item (inserir no início)
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'Version {version}'
    ET.SubElement(item, 'pubDate').text = datetime.utcnow().strftime('%a, %d %b %Y %H:%M:%S +0000')
    
    desc = ET.SubElement(item, 'description')
    desc.text = f'<![CDATA[<h2>Nova Versão {version}</h2><p>Atualização automática via GitHub Release.</p>]]>'
    
    enclosure = ET.SubElement(item, 'enclosure')
    enclosure.set('url', asset_url)
    enclosure.set(f'{{{SPARKLE_NS}}}version', version)
    enclosure.set(f'{{{SPARKLE_NS}}}os', 'windows')
    enclosure.set('length', str(asset_size))
    enclosure.set('type', 'application/octet-stream')
    
    # Mover o novo item para o início
    channel.insert(0, item)
    
    # Salvar com formatação
    tree = ET.ElementTree(root)
    ET.indent(tree, space='  ')
    
    # Adicionar declaração XML manualmente
    with open(appcast_file, 'wb') as f:
        f.write(b'<?xml version="1.0" encoding="UTF-8"?>\n')
        tree.write(f, encoding='utf-8')
    
    print(f"✓ appcast.xml atualizado com versão {version}")
    print(f"  URL: {asset_url}")
    print(f"  Tamanho: {asset_size} bytes")

if __name__ == '__main__':
    if len(sys.argv) != 4:
        print("Uso: python update_appcast_manual.py <versão> <url_asset> <tamanho_bytes>")
        print("Exemplo: python update_appcast_manual.py 1.0.3 https://github.com/.../releases/download/v1.0.3/BackupDatabase-Setup-1.0.3+1.exe 13107200")
        sys.exit(1)
    
    version = sys.argv[1]
    asset_url = sys.argv[2]
    asset_size = sys.argv[3]
    
    update_appcast(version, asset_url, asset_size)

