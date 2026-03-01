# Parse FTP Metrics from Log Files
# Uso: .\scripts\run_parse_ftp_metrics.ps1 [-LogPath "path\to\logs"] [-Export csv|json]
# Exemplo: .\scripts\run_parse_ftp_metrics.ps1 -LogPath "logs" -Export csv

param(
    [string]$LogPath = "",
    [ValidateSet("", "csv", "json")]
    [string]$Export = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $projectRoot) { $projectRoot = (Get-Location).Path }
Set-Location $projectRoot

$args = @()
if ($Export) { $args += "--export"; $args += $Export }
if ($LogPath -and (Test-Path $LogPath)) {
    $files = Get-ChildItem -Path $LogPath -Filter "*.log" -ErrorAction SilentlyContinue
    if ($files) {
        $args += $files.FullName
    } else {
        $args += $LogPath
    }
}

dart run scripts/parse_ftp_metrics.dart @args
