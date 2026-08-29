# Reads appMode from update_context.json for setup.iss (Pascal cannot
# parse JSON reliably). Writes a single trimmed token to OutputPath.

param(
    [Parameter(Mandatory = $true)]
    [string]$ContextPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "encoding_utils.ps1")

if (-not (Test-Path $ContextPath)) {
    exit 0
}

$context = Read-Utf8NoBomFile -Path $ContextPath | ConvertFrom-Json
$mode = [string]$context.appMode
if ([string]::IsNullOrWhiteSpace($mode)) {
    exit 0
}

Write-Utf8NoBomFile -Path $OutputPath -Value $mode.Trim()
exit 0
