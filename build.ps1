param(
  [string]$RepoRoot = $(Split-Path -Parent $PSCommandPath),
  [string]$Version,
  [switch]$NoClean,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$ConfirmPreference = "None"

function Remove-PathSafe([string]$path) {
  if (Test-Path -LiteralPath $path) {
    if ($DryRun) { Write-Host "  (dry-run) Would remove $path"; return }
    Write-Host "  Removing $path"
    Remove-Item -LiteralPath $path -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
  }
}

function Ensure-File([string]$path, [string]$msg) {
  if (-not (Test-Path -LiteralPath $path)) { throw $msg }
}

function Run([string]$cmd, [string[]]$args) {
  Write-Host ">> $cmd $($args -join ' ')"
  if ($DryRun) { Write-Host "  (dry-run) Skipping exec"; return }
  $p = Start-Process -FilePath $cmd -ArgumentList $args -NoNewWindow -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "'$cmd' failed with exit code $($p.ExitCode)" }
}

Write-Host "=== ProjectTracker Build ==="
Write-Host "RepoRoot: $RepoRoot"

Ensure-File (Join-Path $RepoRoot "app.py") "Could not find app.py in $RepoRoot"
Ensure-File (Join-Path $RepoRoot "electron\package.json") "Could not find electron\package.json"

Push-Location $RepoRoot
try {
  if (-not $NoClean) {
    Write-Host "`n[1/5] Cleaning previous outputs (whitelist only)..."
    # PyInstaller outputs
    Remove-PathSafe (Join-Path $RepoRoot "build")
    Remove-PathSafe (Join-Path $RepoRoot "dist")
    Get-ChildItem -LiteralPath $RepoRoot -Filter "*.spec" -File -ErrorAction SilentlyContinue | ForEach-Object {
      if ($DryRun) { Write-Host "  (dry-run) Would remove $($_.FullName)" }
      else { Remove-Item -LiteralPath $_.FullName -Force -Confirm:$false }
    }
    Get-ChildItem -LiteralPath $RepoRoot -Include "warn-*.txt","*.toc","*.pkg" -File -ErrorAction SilentlyContinue | ForEach-Object {
      if ($DryRun) { Write-Host "  (dry-run) Would remove $($_.FullName)" }
      else { Remove-Item -LiteralPath $_.FullName -Force -Confirm:$false }
    }

    # Electron outputs (NOTE: not deleting the electron folder itself)
    Remove-PathSafe (Join-Path $RepoRoot "electron\dist")
    Remove-PathSafe (Join-Path $RepoRoot "electron\out")
    Remove-PathSafe (Join-Path $RepoRoot "electron\build")
    Remove-PathSafe (Join-Path $RepoRoot "electron\.cache")
    # Optional: clear node_modules to force a clean npm ci (commented out)
    # Remove-PathSafe (Join-Path $RepoRoot "electron\node_modules")
  } else {
    Write-Host "`n[1/5] Skipping clean (NoClean)."
  }

  Write-Host "`n[2/5] Preparing Python..."
  Run "python" @("-m","pip","install","--upgrade","pip","setuptools","wheel")
  Run "python" @("-m","pip","install","flask","pyinstaller")

  Write-Host "`n[3/5] Building backend with PyInstaller..."
  $pyiArgs = @(
    "app.py","--onefile",
    "--add-data","templates;templates",
    "--add-data","static;static",
    "--name","projecttracker-backend"
  )
  Run "python" @("-m","PyInstaller") + $pyiArgs

  $backendExe = Join-Path $RepoRoot "dist\projecttracker-backend.exe"
  Ensure-File $backendExe "PyInstaller build missing: $backendExe"

  if ($Version) {
    Write-Host "`n[3.5/5] Bumping Electron version to $Version..."
    $pkgPath = Join-Path $RepoRoot "electron\package.json"
    $pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json
    $pkg.version = $Version
    ($pkg | ConvertTo-Json -Depth 100) | Set-Content -Path $pkgPath -Encoding UTF8
  }

  Write-Host "`n[4/5] Building Electron app..."
  Push-Location (Join-Path $RepoRoot "electron")
  try {
    if (-not $DryRun) { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force | Out-Null }
    if (Test-Path ".\package-lock.json") { Run "npm" @("ci") } else { Run "npm" @("install") }
    Run "npm" @("run","dist")
  } finally { Pop-Location }

  Write-Host "`n[5/5] Done."
  Write-Host "Backend EXE : $backendExe"
  $electronDist = Join-Path $RepoRoot "electron\dist"
  if (Test-Path $electronDist) {
    $portable = Get-ChildItem -LiteralPath $electronDist -Filter "projecttracker-electron*.exe" -File -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($portable) {
      Write-Host "Electron EXE: $($portable.FullName)"
      if (-not $DryRun) {
        $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $portable.FullName
        Write-Host "SHA256      : $($hash.Hash)"
        Invoke-Item $electronDist
      }
    }
  }
}
finally { Pop-Location }
