# Shared UTF-8 helpers for installer PowerShell scripts (no BOM).

$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    [System.IO.File]::WriteAllText($Path, $Value, $script:Utf8NoBom)
}

function Read-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return [System.IO.File]::ReadAllText($Path, $script:Utf8NoBom)
}
