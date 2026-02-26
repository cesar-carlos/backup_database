# Script para sincronizar appcast.xml com todos os releases do GitHub
# Busca os releases via API do GitHub e atualiza o appcast.xml

$ErrorActionPreference = "Stop"

$REPO = "cesar-carlos/backup_database"
$SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
$appcastFile = "appcast.xml"

Write-Host "Sincronizando appcast.xml com releases do GitHub..." -ForegroundColor Cyan
Write-Host ""

# Buscar releases do GitHub
Write-Host "Buscando releases do GitHub..." -ForegroundColor Yellow
try {
    $releasesUrl = "https://api.github.com/repos/$REPO/releases"
    $releasesResponse = Invoke-RestMethod -Uri $releasesUrl -Method Get
    Write-Host "Encontrados $($releasesResponse.Count) releases" -ForegroundColor Green
}
catch {
    Write-Host "ERRO ao buscar releases: $_" -ForegroundColor Red
    exit 1
}

# Criar ou carregar appcast.xml
if (Test-Path $appcastFile) {
    [xml]$appcast = Get-Content $appcastFile -Encoding UTF8
    $channel = $appcast.rss.channel
    
    # Limpar todos os itens existentes
    $itemsToRemove = @()
    foreach ($node in $channel.ChildNodes) {
        if ($node.Name -eq "item") {
            $itemsToRemove += $node
        }
    }
    foreach ($item in $itemsToRemove) {
        $channel.RemoveChild($item) | Out-Null
    }
    Write-Host "Arquivo appcast.xml carregado, itens antigos removidos" -ForegroundColor Gray
}
else {
    # Criar novo appcast.xml
    $appcast = New-Object System.Xml.XmlDocument
    $rss = $appcast.CreateElement("rss")
    $rss.SetAttribute("version", "2.0")
    $rss.SetAttribute("xmlns:sparkle", $SPARKLE_NS)
    $appcast.AppendChild($rss) | Out-Null
    
    $channel = $appcast.CreateElement("channel")
    $rss.AppendChild($channel) | Out-Null
    
    $title = $appcast.CreateElement("title")
    $title.InnerText = "Backup Database Updates"
    $channel.AppendChild($title) | Out-Null
    
    $link = $appcast.CreateElement("link")
    $link.InnerText = "https://github.com/$REPO/releases"
    $channel.AppendChild($link) | Out-Null
    
    $description = $appcast.CreateElement("description")
    $description.InnerText = "Atualizacoes do Backup Database"
    $channel.AppendChild($description) | Out-Null
    
    Write-Host "Novo appcast.xml criado" -ForegroundColor Gray
}

# Processar releases
$itemsAdded = 0
foreach ($release in $releasesResponse) {
    # Pular drafts e prereleases
    if ($release.draft -eq $true -or $release.prerelease -eq $true) {
        Write-Host "Pulando release $($release.tag_name) (draft ou prerelease)" -ForegroundColor Yellow
        continue
    }
    
    $tagName = $release.tag_name
    # Remover prefixo 'v' se existir
    if ($tagName.StartsWith("v")) {
        $version = $tagName.Substring(1)
    }
    else {
        $version = $tagName
    }
    
    # Encontrar asset .exe
    $exeAsset = $null
    foreach ($asset in $release.assets) {
        if ($asset.name -like "*.exe") {
            $exeAsset = $asset
            break
        }
    }
    
    if ($exeAsset -eq $null) {
        Write-Host "AVISO: Nenhum asset .exe encontrado no release $tagName" -ForegroundColor Yellow
        continue
    }
    
    $assetUrl = $exeAsset.browser_download_url
    $assetSize = $exeAsset.size
    
    # Criar item
    $item = $appcast.CreateElement("item")
    $channel.AppendChild($item) | Out-Null
    
    $title = $appcast.CreateElement("title")
    $title.InnerText = "Version $version"
    $item.AppendChild($title) | Out-Null
    
    # Usar data de publicação do release
    $pubDate = $appcast.CreateElement("pubDate")
    try {
        $publishedDate = [DateTime]::Parse($release.published_at)
        $pubDateStr = $publishedDate.ToUniversalTime().ToString("ddd, dd MMM yyyy HH:mm:ss +0000")
    }
    catch {
        $pubDateStr = (Get-Date).ToUniversalTime().ToString("ddd, dd MMM yyyy HH:mm:ss +0000")
    }
    $pubDate.InnerText = $pubDateStr
    $item.AppendChild($pubDate) | Out-Null
    
    $desc = $appcast.CreateElement("description")
    if ($release.body) {
        $body = $release.body
    }
    else {
        $body = "Atualizacao automatica via GitHub Release."
    }
    $desc.InnerText = "<![CDATA[<h2>Versao $version</h2><p>$body</p>]]>"
    $item.AppendChild($desc) | Out-Null
    
    $enclosure = $appcast.CreateElement("enclosure")
    $enclosure.SetAttribute("url", $assetUrl)
    $enclosure.SetAttribute("sparkle:version", $version)
    $enclosure.SetAttribute("sparkle:os", "windows")
    $enclosure.SetAttribute("length", $assetSize.ToString())
    $enclosure.SetAttribute("type", "application/octet-stream")
    $item.AppendChild($enclosure) | Out-Null
    
    $itemsAdded++
    Write-Host "Adicionado release $tagName (versao $version)" -ForegroundColor Green
}

# Salvar appcast.xml
$appcast.Save($appcastFile)

Write-Host ""
Write-Host "appcast.xml atualizado com $itemsAdded releases" -ForegroundColor Green
Write-Host "Arquivo salvo: $appcastFile" -ForegroundColor Gray
