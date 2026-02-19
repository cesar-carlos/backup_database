param(
  [switch]$DartMode,
  [int]$FailUnder = 0,
  [string]$TestTargets = ''
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$message) {
  Write-Host "==> $message" -ForegroundColor Cyan
}

function Test-IsIgnoredFile([string]$path) {
  $normalized = $path.Replace('\', '/')
  $ignorePatterns = @(
    '/test/',
    '.g.dart',
    '.freezed.dart',
    '.mocks.dart',
    '/generated/',
    '/gen/'
  )

  foreach ($pattern in $ignorePatterns) {
    if ($normalized.Contains($pattern)) {
      return $true
    }
  }
  return $false
}

function Filter-LcovFile([string]$inputPath, [string]$outputPath) {
  $lines = Get-Content $inputPath
  $result = New-Object System.Collections.Generic.List[string]
  $currentFile = $null
  $currentBlock = New-Object System.Collections.Generic.List[string]

  foreach ($line in $lines) {
    if ($line.StartsWith('SF:')) {
      if ($currentBlock.Count -gt 0 -and $currentFile -ne $null) {
        if (-not (Test-IsIgnoredFile $currentFile)) {
          foreach ($blockLine in $currentBlock) { $result.Add($blockLine) }
        }
      }
      $currentBlock.Clear()
      $currentFile = $line.Substring(3)
      $currentBlock.Add($line)
      continue
    }

    if ($currentBlock.Count -gt 0) {
      $currentBlock.Add($line)
      if ($line -eq 'end_of_record') {
        if (-not (Test-IsIgnoredFile $currentFile)) {
          foreach ($blockLine in $currentBlock) { $result.Add($blockLine) }
        }
        $currentBlock.Clear()
        $currentFile = $null
      }
    }
  }

  if ($currentBlock.Count -gt 0 -and $currentFile -ne $null) {
    if (-not (Test-IsIgnoredFile $currentFile)) {
      foreach ($blockLine in $currentBlock) { $result.Add($blockLine) }
    }
  }

  $result | Set-Content $outputPath
}

function Get-LcovCoverage([string]$lcovPath) {
  $lines = Get-Content $lcovPath
  $total = 0
  $hit = 0
  foreach ($line in $lines) {
    if ($line.StartsWith('DA:')) {
      $parts = $line.Substring(3).Split(',')
      if ($parts.Count -ge 2) {
        $total++
        if ([int]$parts[1] -gt 0) {
          $hit++
        }
      }
    }
  }

  if ($total -eq 0) {
    return 0.0
  }

  return [math]::Round(($hit * 100.0 / $total), 2)
}

if ($DartMode) {
  Write-Step "Running Dart coverage with package:coverage"
  $cmd = "dart run coverage:test_with_coverage"
  if ($FailUnder -gt 0) {
    $cmd += " --fail-under $FailUnder"
  }
  Invoke-Expression $cmd
  exit $LASTEXITCODE
}

Write-Step "Running Flutter tests with coverage"
if (-not [string]::IsNullOrWhiteSpace($TestTargets)) {
  $targets = $TestTargets.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
  flutter test --coverage @targets
} else {
  flutter test --coverage
}
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

$lcovPath = "coverage/lcov.info"
$filteredLcovPath = "coverage/lcov.filtered.info"

if (-not (Test-Path $lcovPath)) {
  Write-Error "Coverage file not found: $lcovPath"
  exit 1
}

Write-Step "Filtering generated/test files from lcov"
Filter-LcovFile -inputPath $lcovPath -outputPath $filteredLcovPath

$coverage = Get-LcovCoverage -lcovPath $filteredLcovPath
Write-Host ("Line coverage (filtered): {0}%" -f $coverage) -ForegroundColor Green
Write-Host ("Filtered report: {0}" -f $filteredLcovPath) -ForegroundColor Yellow

if ($FailUnder -gt 0 -and $coverage -lt $FailUnder) {
  Write-Error ("Coverage {0}% is below threshold {1}%." -f $coverage, $FailUnder)
  exit 1
}

Write-Step "Coverage completed"
