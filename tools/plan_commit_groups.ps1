# Stages plano_refatoracao changes into logical commits (run from repo root).
# Usage:
#   .\tools\plan_commit_groups.ps1 -DryRun
#   .\tools\plan_commit_groups.ps1 -Execute

param(
  [switch]$DryRun,
  [switch]$Execute
)

if (-not $Execute -and -not $DryRun) {
  $DryRun = $true
  Write-Host "Default: -DryRun. Pass -Execute to create commits."
}

$groups = @(
  @{
    Message = "feat(domain): migrate core entities to freezed`n`nSchedule composition, SGBD configs implement DatabaseConnectionConfig, BackupLog/BackupHistory/BackupExecutionContext freezed, and domain tests."
    Paths = @("lib/domain", "test/unit/domain")
  },
  @{
    Message = "feat(app,infra,core): firebird backup, schedule pipeline, and DI`n`nApplication strategies, infrastructure services/repos, core DI and Firebird helpers; unit tests for application/infrastructure/core."
    Paths = @("lib/application", "lib/infrastructure", "lib/core", "test/unit/application", "test/unit/infrastructure", "test/unit/core")
  },
  @{
    Message = "feat(presentation): design system, skeletons, and Windows chrome`n`nAtomic widget folders, skeleton loading, Mica bootstrap, theme/density providers; widget, golden, and presentation unit tests."
    Paths = @("lib/presentation", "lib/main.dart", "test/unit/presentation", "test/widget", "test/golden", "test/helpers", "widgetbook")
  },
  @{
    Message = "chore(ci,tools): coverage, design guard, and PR tooling`n`nCodecov upload, design_system_guard with enforce-target-size, sgbd_loc_report, pull request template, and workflow updates."
    Paths = @(".github", "tools", "scripts", "analysis_options.yaml")
  },
  @{
    Message = "docs: ADRs, plan status, onboarding, and smoke runbooks`n`nArchitecture decisions M1/M6-M14, refactoring plan checkboxes, design-system onboarding, and Windows Mica smoke checklist."
    Paths = @("docs", "README.md", "design-tokens")
  },
  @{
    Message = "chore(deps): pubspec and lockfile for refactors`n`nDependencies and lockfile updates supporting freezed, shimmer, flutter_acrylic, system_theme, and related packages."
    Paths = @("pubspec.yaml", "pubspec.lock")
  }
)

function Stage-Group {
  param([string[]]$Paths)
  foreach ($p in $Paths) {
    if (Test-Path $p) {
      git add -A -- $p
    }
  }
}

$remaining = git status --short
if (-not $remaining) {
  Write-Host "Working tree clean - nothing to commit."
  exit 0
}

foreach ($g in $groups) {
  $title = ($g.Message -split "`n")[0]
  Write-Host ""
  Write-Host "=== $title ===" -ForegroundColor Cyan
  if ($DryRun) {
    foreach ($p in $g.Paths) {
      if (Test-Path $p) {
        Write-Host "  git add -A -- $p"
      }
    }
    Write-Host "  git commit -m <message>"
    continue
  }
  if ($Execute) {
    Stage-Group -Paths $g.Paths
    $staged = git diff --cached --name-only
    if (-not $staged) {
      Write-Host "  (skip: no staged changes for this group)" -ForegroundColor Yellow
      continue
    }
    git commit -m $g.Message
    if ($LASTEXITCODE -ne 0) {
      Write-Error "Commit failed."
      exit 1
    }
  }
}

if ($Execute) {
  $left = git status --short
  if ($left) {
    Write-Host ""
    Write-Host "Uncommitted files remain:" -ForegroundColor Yellow
    $left | ForEach-Object { Write-Host $_ }
    Write-Host "Stage manually or extend plan_commit_groups.ps1"
    exit 1
  }
  Write-Host ""
  Write-Host "All groups committed." -ForegroundColor Green
}
