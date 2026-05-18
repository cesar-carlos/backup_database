# M14 smoke helper (Windows only). Run from repo root on Win10 or Win11.
# See docs/notes/smoke_windows_mica_m14.md for acceptance criteria.

$ErrorActionPreference = "Stop"

if (-not $IsWindows) {
  Write-Error "This smoke script must run on Windows."
}

$os = Get-CimInstance Win32_OperatingSystem
$build = [int]$os.BuildNumber
$isWin11 = $build -ge 22000

Write-Host "=== M14 smoke: Windows native chrome ===" -ForegroundColor Cyan
Write-Host "OS: $($os.Caption) (build $build)"
Write-Host "Win11+ (Mica expected): $isWin11"
Write-Host "Date: $(Get-Date -Format o)"
Write-Host ""

$scenarios = @(
  @{ Id = "A"; Mica = $true;  Dark = $false; Note = "Win10/11 Mica on, light" },
  @{ Id = "B"; Mica = $false; Dark = $true;  Note = "Mica off, dark" },
  @{ Id = "C"; Mica = $true;  Dark = $false; Note = "Win11 Mica on, light (visual)" },
  @{ Id = "D"; Mica = $true;  Dark = $true;  Note = "Win11 Mica on, dark toggle" },
  @{ Id = "E"; Mica = $false; Dark = $false; Note = "Mica disabled" },
  @{ Id = "F"; Mica = $null; Dark = $null; Note = "System accent on (settings)" },
  @{ Id = "G"; Mica = $null; Dark = $null; Note = "System accent off (brand)" }
)

Write-Host "Manual steps per scenario (see runbook):" -ForegroundColor Yellow
Write-Host "  1. flutter run -d windows  (or installed release build)"
Write-Host "  2. Settings > General > Appearance"
Write-Host "  3. Toggle Mica / system accent / dark theme per scenario"
Write-Host "  4. Resize window; restart app; confirm no crash"
Write-Host ""

foreach ($s in $scenarios) {
  Write-Host "--- Scenario $($s.Id): $($s.Note) ---" -ForegroundColor Green
  if ($null -ne $s.Mica) {
    Write-Host "  Mica backdrop: $($s.Mica)"
    Write-Host "  Dark theme: $($s.Dark)"
  }
  $ok = Read-Host "  Pass? (y/n/skip)"
  if ($ok -eq "n") {
    Write-Host "FAILED scenario $($s.Id)" -ForegroundColor Red
    exit 1
  }
}

Write-Host ""
Write-Host "All recorded scenarios passed." -ForegroundColor Green
Write-Host "Mark M14 in docs/notes/plano_refatoracao_e_melhorias_2026-04-19.md when done."
