<# 
  build.ps1 — One-click rebuild (Windows)

  - Cleans previous PyInstaller and Electron outputs
  - Builds backend EXE via PyInstaller
  - (Optionally) bumps electron/package.json version
  - Builds Electron portable exe via electron-builder

  Usage:
    # default (clean + build)
    powershell -ExecutionPolicy Bypass -File .\build.ps1

    # specify repo path (if running from elsewhere)
    powershell -ExecutionPolicy Bypass -File .\build.ps1 -RepoRoot "C:\Users\Jack\Documents\GitHub\ElectronProjectTracker"

    # bump Electron version before building
    powershell -ExecutionPolicy Bypass -File .\build.ps1 -Version 0.1.1
#>

param(
  [string]$RepoRoot = $(Split-Path -Parent $PSCommandPath),   # assumes script is in repo root
  [string]$Version,                                           # optional: set electron/package.json version
  [switch]$NoClean                                            # optional: skip cleaning
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Remove-PathSafe([string]$path) {
  if (Test-Path -LiteralPath $path) {
    Write-Host "  Removing $path"
    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Ensure-File([string]$path, [string]$errorMsg) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw $errorMsg
  }
}

function Run([string]$cmd, [string[]]$args) {
  Write-Host ">> $cmd $($args -join ' ')"
  $p = Start-Process -FilePath $cmd -ArgumentList $args -NoNewWindow -Wait -PassThru
  if ($p.ExitCode -ne 0) {
    throw "'$cmd' failed with exit code $($p.ExitCode)"
  }
}

Write-Host "=== ProjectTracker Build ==="
Write-Host "RepoRoot: $RepoRoot"

# 0) Sanity checks
Ensure-File (Join-Path $RepoRoot "app.py") "Could not find app.py in $RepoRoot"
Ensure-File (Join-Path $RepoRoot "electron\package.json") "Could not find electron\package.json"

Push-Location $RepoRoot
try {
  # 1) Optional clean
  if (-not $NoClean) {
    Write-Host "`n[1/5] Cleaning previous outputs..."
    # PyInstaller outputs in repo root
    Remove-PathSafe (Join-Path $RepoRoot "build")
    Remove-PathSafe (Join-Path $RepoRoot "dist")
    Get-ChildItem -LiteralPath $RepoRoot -Filter "*.spec" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $RepoRoot -Include "warn-*.txt","*.toc","*.pkg" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

    # Electron outputs
    Remove-PathSafe (Join-Path $RepoRoot "electron\dist")
    Remove-PathSafe (Join-Path $RepoRoot "electron\out")
    Remove-PathSafe (Join-Path $RepoRoot "electron\build")
    Remove-PathSafe (Join-Path $RepoRoot "electron\.cache")
  } else {
    Write-Host "`n[1/5] Skipping clean (NoClean)."
  }

  # 2) Ensure Python deps, then build backend exe
  Write-Host "`n[2/5] Preparing Python..."
  Run "python" @("-m","pip","install","--upgrade","pip","setuptools","wheel")
  Run "python" @("-m","pip","install","flask","pyinstaller")

  Write-Host "`n[3/5] Building backend with PyInstaller..."
  $pyiArgs = @(
    "app.py",
    "--onefile",
    "--add-data","templates;templates",
    "--add-data","static;static",
    "--name","projecttracker-backend"
  )
  Run "python" @("-m","PyInstaller") + $pyiArgs

  $backendExe = Join-Path $RepoRoot "dist\projecttracker-backend.exe"
  Ensure-File $backendExe "PyInstaller build missing: $backendExe"

  # 3.5) Optional: bump Electron version
  if ($Version) {
    Write-Host "`n[3.5/5] Bumping Electron version to $Version..."
    $pkgPath = Join-Path $RepoRoot "electron\package.json"
    $pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json
    $pkg.version = $Version
    ($pkg | ConvertTo-Json -Depth 100) | Set-Content -Path $pkgPath -Encoding UTF8
  }

  # 4) Install Node deps & build Electron
  Write-Host "`n[4/5] Building Electron app..."
  Push-Location (Join-Path $RepoRoot "electron")
  try {
    # Allow npm.ps1 to run in locked-down envs
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force | Out-Null

    # Use npm ci if lockfile exists; otherwise fallback to install
    if (Test-Path ".\package-lock.json") {
      Run "npm" @("ci")
    } else {
      Run "npm" @("install")
    }

    Run "npm" @("run","dist")
  } finally {
    Pop-Location
  }

  # 5) Summarize outputs
  Write-Host "`n[5/5] Done."
  $electronDist = Join-Path $RepoRoot "electron\dist"
  Ensure-File $electronDist "Electron dist folder not found: $electronDist"
  $portable = Get-ChildItem -LiteralPath $electronDist -Filter "projecttracker-electron*.exe" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1

  Write-Host "Backend EXE : $backendExe"
  if ($portable) {
    Write-Host "Electron EXE: $($portable.FullName)"
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $portable.FullName
    Write-Host "SHA256      : $($hash.Hash)"
    Invoke-Item $electronDist
  } else {
    Write-Warning "Could not locate the packaged Electron EXE in $electronDist"
  }
}
finally {
  Pop-Location
}
