param(
    [ValidateSet('Quick', 'Full', 'Installer')]
    [string]$Mode = 'Quick'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent

function Invoke-Checked {
    param([string]$Command, [string[]]$Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Falha em $Command (codigo $LASTEXITCODE). Preflight interrompido."
    }
}

Push-Location $projectRoot
try {
    if ($Mode -eq 'Installer') {
        Invoke-Checked git @('diff', '--quiet', 'HEAD')
        $untracked = @(git ls-files --others --exclude-standard)
        if ($LASTEXITCODE -ne 0 -or $untracked.Count -ne 0) {
            throw 'Salve todos os fontes em um commit antes de gerar o instalador de release.'
        }
        if ((Get-FileHash .env).Hash -ne (Get-FileHash .env.example).Hash) {
            throw 'Use .env.example como .env em um checkout dedicado para nao embutir configuracoes locais.'
        }
    }

    Invoke-Checked flutter @('pub', 'get')
    Invoke-Checked dart @('format', '--set-exit-if-changed', '--output=none', 'lib', 'test', 'tools')
    Invoke-Checked py @('-3', 'scripts/scan_encoding.py')
    Invoke-Checked py @('-3', 'scripts/verify_windows_icons.py')
    Invoke-Checked py @('-3', 'test/scripts/test_windows_icon_utils.py')
    Invoke-Checked dart @('run', 'tools/generate_tokens.dart', '--check')
    Invoke-Checked dart @('run', 'tools/design_system_guard.dart', '--fail-on-findings', '--enforce-target-size')
    Invoke-Checked flutter @('analyze', '--no-fatal-infos')

    # Includes the service/rollback/ACL regressions that cannot run on Linux.
    if ($Mode -eq 'Quick') {
        Invoke-Checked flutter @('test',
            'test/unit/installer/winsw_migration_test.dart',
            'test/unit/installer/rollback_update_test.dart',
            'test/unit/infrastructure/repositories/administrative_database_test.dart')
    } else {
        Invoke-Checked flutter @('test', 'test/unit/', '--reporter', 'compact')
        Invoke-Checked flutter @('test', 'test/widget', '--reporter', 'compact')
        Push-Location widgetbook
        try {
            Invoke-Checked flutter @('pub', 'get')
            Invoke-Checked flutter @('analyze', '--no-fatal-infos')
        } finally { Pop-Location }
    }

    if ($Mode -eq 'Installer') {
        # Revalidate the incremental build instead of trusting only EXE mtime.
        Invoke-Checked flutter @('build', 'windows', '--release')
        Invoke-Checked py @('-3', 'installer/build_installer.py')
        # Icon/version generation must not silently change the tested sources.
        Invoke-Checked git @('diff', '--quiet', 'HEAD')
        $version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value.Split('+')[0]
        $installer = Join-Path $projectRoot "installer/dist/BackupDatabase-Setup-$version.exe"
        $sha = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
        $report = [ordered]@{
            version = $version
            commit = (git rev-parse HEAD).Trim()
            tree = (git rev-parse 'HEAD^{tree}').Trim()
            sha256 = $sha
            bytes = (Get-Item -LiteralPath $installer).Length
            validation = 'Windows full unit/widget/analyze and installer'
        }
        $report | ConvertTo-Json | Set-Content -LiteralPath "$installer.validation.json" -Encoding utf8
    }
    Write-Host "Preflight $Mode concluido."
} finally {
    Pop-Location
}
