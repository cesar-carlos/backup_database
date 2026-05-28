# Faz merge de .env.example -> .env mantendo overrides do usuário.
#
# Estratégia de merge (audit 2026-05-28):
#
# 1. **Chaves "system-managed"** (`$systemManagedKeys`) são SEMPRE
#    sobrescritas pelo valor do `.env.example`. Inclui `APP_VERSION` /
#    `APP_NAME` — não fazia sentido preservar valor stale de 2.1.3
#    quando o instalador 3.3.x sabe a versão correta. Diagnóstico
#    histórico ficava mostrando versão errada em logs.
#
# 2. **Resto** mantém o comportamento original: só adiciona chaves
#    novas, preserva customização do usuário (ex.: FTP_IT_HOST,
#    BACKUP_DATABASE_LICENSE_*, SINGLE_INSTANCE_ENABLED=false em dev).
#
# 3. **Validação pós-merge**: chaves declaradas em `$criticalKeys`
#    DEVEM estar presentes e não-vazias após o merge. Se faltarem, o
#    script sai com `exit 2` para o instalador abortar (e o `setup.iss`
#    pode loggar Warning para o usuário). Isso evita o caso da auditoria
#    em que o `.env` foi escrito sem `AUTO_UPDATE_FEED_URL` e o
#    auto-update ficou silenciosamente quebrado por semanas.

param(
    [Parameter(Mandatory = $true)]
    [string]$ExamplePath,
    [Parameter(Mandatory = $true)]
    [string]$TargetPath,
    [string]$LegacyPath = "",
    [string]$BackupPath = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "encoding_utils.ps1")

$script:MergeMarker = "# Added by installer merge"

# Chaves cuja autoridade pertence ao instalador — sempre sobrescritas a
# partir do .env.example. NÃO inclua aqui chaves que o usuário tem
# legitimidade de customizar (URLs de feed, credenciais, flags de dev).
$script:SystemManagedKeys = @(
    'APP_VERSION',
    'APP_NAME'
)

# Chaves críticas — se faltarem após o merge, o exit code é não-zero
# para que o instalador possa reagir (caller decide se aborta ou
# apenas registra warning).
$script:CriticalKeys = @(
    'AUTO_UPDATE_FEED_URL'
)

function ConvertTo-KeyMap([string]$Path) {
    $map = @{}
    if (-not (Test-Path $Path)) {
        return $map
    }

    foreach ($line in Get-Content -Path $Path) {
        if ($line -match '^\s*#' -or $line -notmatch '=') {
            continue
        }

        $parts = $line.Split('=', 2)
        $key = $parts[0].Trim()
        if ([string]::IsNullOrWhiteSpace($key)) {
            continue
        }
        $map[$key] = $line
    }

    return $map
}

function Get-KeyValue([string]$Line) {
    if ([string]::IsNullOrEmpty($Line)) { return "" }
    $parts = $Line.Split('=', 2)
    if ($parts.Length -lt 2) { return "" }
    return $parts[1].Trim()
}

function Set-KeyInTargetFile([string]$TargetPath, [string]$Key, [string]$NewLine) {
    # Reescreve o arquivo substituindo a linha da chave dada.
    $content = Read-Utf8NoBomFile -Path $TargetPath
    $lines = $content -split "(`r`n|`r|`n)"
    $updated = New-Object System.Text.StringBuilder
    $found = $false

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        # Preserva separadores de linha (eles vêm intercalados pelo -split)
        if ($line -match '^(\r\n|\r|\n)$') {
            [void]$updated.Append($line)
            continue
        }
        if (-not $found -and $line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=') {
            $currentKey = $Matches[1].Trim()
            if ($currentKey -eq $Key) {
                [void]$updated.Append($NewLine)
                $found = $true
                continue
            }
        }
        [void]$updated.Append($line)
    }

    if (-not $found) {
        # Chave não existia no target — append (preservando trailing newline).
        if ($content.Length -gt 0 -and -not $content.EndsWith([Environment]::NewLine)) {
            [void]$updated.AppendLine()
        }
        [void]$updated.AppendLine($NewLine)
    }

    Write-Utf8NoBomFile -Path $TargetPath -Value $updated.ToString()
}

if (-not (Test-Path $TargetPath) -and -not [string]::IsNullOrWhiteSpace($LegacyPath) -and (Test-Path $LegacyPath)) {
    Copy-Item -Path $LegacyPath -Destination $TargetPath -Force
    if (-not [string]::IsNullOrWhiteSpace($BackupPath) -and -not (Test-Path $BackupPath)) {
        Copy-Item -Path $LegacyPath -Destination $BackupPath -Force
    }
}

if (-not (Test-Path $TargetPath) -and (Test-Path $ExamplePath)) {
    Copy-Item -Path $ExamplePath -Destination $TargetPath -Force
}

if (-not (Test-Path $ExamplePath) -or -not (Test-Path $TargetPath)) {
    # Sem fontes para fazer merge — encerra mas ainda valida críticas.
    $finalForGate = ConvertTo-KeyMap -Path $TargetPath
    $missingCritical = @()
    foreach ($k in $script:CriticalKeys) {
        $v = Get-KeyValue -Line $finalForGate[$k]
        if ([string]::IsNullOrWhiteSpace($v)) {
            $missingCritical += $k
        }
    }
    if ($missingCritical.Count -gt 0) {
        [Console]::Error.WriteLine(
            "merge_env.ps1: Chaves criticas ausentes apos merge: " +
            "$($missingCritical -join ', ')"
        )
        exit 2
    }
    exit 0
}

$exampleMap = ConvertTo-KeyMap -Path $ExamplePath
$targetMap = ConvertTo-KeyMap -Path $TargetPath
$missingLines = New-Object System.Collections.Generic.List[string]

# 1) Sobrescrever chaves system-managed quando elas existem no example
foreach ($key in $script:SystemManagedKeys) {
    if (-not $exampleMap.ContainsKey($key)) { continue }
    $exampleLine = $exampleMap[$key]
    if ($targetMap.ContainsKey($key)) {
        $currentLine = $targetMap[$key]
        if ($currentLine -ne $exampleLine) {
            Set-KeyInTargetFile -TargetPath $TargetPath -Key $key -NewLine $exampleLine
            Write-Host "Atualizada chave system-managed: $key"
        }
    } else {
        # Não existe no target — vai cair no missingLines normal abaixo
    }
}

# 2) Recarregar target depois das updates system-managed
$targetMap = ConvertTo-KeyMap -Path $TargetPath

# 3) Adicionar chaves faltantes
foreach ($key in $exampleMap.Keys) {
    if (-not $targetMap.ContainsKey($key)) {
        $missingLines.Add($exampleMap[$key])
    }
}

if ($missingLines.Count -gt 0) {
    $content = Read-Utf8NoBomFile -Path $TargetPath
    $merged = New-Object System.Text.StringBuilder
    if ($content.Length -gt 0) {
        [void]$merged.Append($content)
        if (-not $content.EndsWith([Environment]::NewLine)) {
            [void]$merged.AppendLine()
        }
    }

    # Evita acumular varios marcadores ao longo de updates incrementais;
    # so adiciona se a ultima linha nao-vazia ja nao for o marcador atual.
    $trimmedContent = $content.TrimEnd()
    $contentLines = if ($trimmedContent.Length -gt 0) {
        $trimmedContent -split "(`r`n|`r|`n)"
    } else {
        @()
    }
    $lastLine = ($contentLines | Where-Object { $_ -and $_ -notmatch '^(\r\n|\r|\n)$' } | Select-Object -Last 1)
    if ([string]::IsNullOrWhiteSpace($lastLine) -or $lastLine.TrimEnd() -ne $script:MergeMarker) {
        [void]$merged.AppendLine($script:MergeMarker)
    }

    foreach ($line in $missingLines) {
        [void]$merged.AppendLine($line)
    }
    Write-Utf8NoBomFile -Path $TargetPath -Value $merged.ToString()
}

# 4) Validação final — chaves críticas DEVEM estar presentes e não-vazias.
$finalMap = ConvertTo-KeyMap -Path $TargetPath
$missingCritical = @()
foreach ($k in $script:CriticalKeys) {
    $v = Get-KeyValue -Line $finalMap[$k]
    if ([string]::IsNullOrWhiteSpace($v)) {
        $missingCritical += $k
    }
}

if ($missingCritical.Count -gt 0) {
    # `Write-Error` com `$ErrorActionPreference=Stop` aborta o script
    # antes do `exit`, deixando exit code 1 (genérico). Para garantir
    # exit code 2 (semântico para "config critica ausente") usamos
    # `[Console]::Error.WriteLine` direto + `exit 2` controlado.
    [Console]::Error.WriteLine(
        "merge_env.ps1: Chaves criticas ausentes apos merge em " +
        "'$TargetPath': $($missingCritical -join ', '). " +
        "Auto-update e features dependentes ficarao desabilitadas ate corrigir."
    )
    exit 2
}

exit 0

# Fallback dentro do primeiro early-exit do script (sem .env.example),
# replicado aqui por consistencia caso o fluxo entre nele futuramente.
