# Faz merge de .env.example -> .env sem sobrescrever chaves existentes.

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

function Parse-KeyMap {
    param(
        [string]$Path
    )

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

if (-not (Test-Path $TargetPath) -and -not [string]::IsNullOrWhiteSpace($LegacyPath) -and (Test-Path $LegacyPath)) {
    Copy-Item -Path $LegacyPath -Destination $TargetPath -Force
    if (-not [string]::IsNullOrWhiteSpace($BackupPath) -and -not (Test-Path $BackupPath)) {
        Copy-Item -Path $LegacyPath -Destination $BackupPath -Force
    }
}

if (-not (Test-Path $TargetPath) -and (Test-Path $ExamplePath)) {
    Copy-Item -Path $ExamplePath -Destination $TargetPath -Force
    exit 0
}

if (-not (Test-Path $ExamplePath) -or -not (Test-Path $TargetPath)) {
    exit 0
}

$exampleMap = Parse-KeyMap -Path $ExamplePath
$targetMap = Parse-KeyMap -Path $TargetPath
$missingLines = New-Object System.Collections.Generic.List[string]

foreach ($key in $exampleMap.Keys) {
    if (-not $targetMap.ContainsKey($key)) {
        $missingLines.Add($exampleMap[$key])
    }
}

if ($missingLines.Count -eq 0) {
    exit 0
}

$content = Read-Utf8NoBomFile -Path $TargetPath
$merged = New-Object System.Text.StringBuilder
if ($content.Length -gt 0) {
    [void]$merged.Append($content)
    if (-not $content.EndsWith([Environment]::NewLine)) {
        [void]$merged.AppendLine()
    }
}
[void]$merged.AppendLine("# Added by installer merge")
foreach ($line in $missingLines) {
    [void]$merged.AppendLine($line)
}
Write-Utf8NoBomFile -Path $TargetPath -Value $merged.ToString()
