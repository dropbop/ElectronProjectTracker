param(
  [string]$RepoRoot = $(Split-Path -Parent $PSCommandPath),  # path to repo (defaults to this script's folder)
  [switch]$DryRun,                                          # preview actions only
  [switch]$SkipInstall                                      # skip pip/npm installs
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$ConfirmPreference = "None"

# ---- CONFIG: filenames (change only if you rename binaries) ----
$BackendExeName   = "projecttracker-backend.exe"
$ElectronExeGlob  = "projecttracker-electron*.exe"

# ---- Helpers ----
function Say($msg) { Write-Host $msg }
function Do($cmd, $args) {
  Say ">> $cmd $($args -join ' ')"
  if ($DryRun) { Say "   (dry-run) Skipping exec"; return }
  & $cmd @args
  if ($LASTEXITCODE -ne 0) { throw "'$cmd' failed with exit code $LASTEXITCODE" }
}
function Remove-FileIfExists([string]$path) {
  if (Test-Path -LiteralPath $path -PathType Leaf) {
    if ($DryRun) { Say "   (dry-run) Would remove $path"; return }
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    Say "   Removed $path"
  } else {
    Say "   (skip) Not found: $path"
  }
}

# ---- Start ----
Say "=== ProjectTracker Build (safe) ==="
Say "RepoRoot: $RepoRoot"

# Sanity checks
if (-not (Test-Path (Join-Path $RepoRoot "app.py"))) { throw "app.py not found in $RepoRoot" }
if (-not (Test-Path (Join-Path $RepoRoot "electron\package.json"))) { throw "electron\package.json not found" }

Push-Location $RepoRoot
try {
  # Paths
  $backendExe = Join-Path $RepoRoot "dist\$BackendExeName"
  $electronDir = Join-Path $RepoRoot "electron"
  $electronDist = Join-Path $electronDir "dist"

  # 1) Clean ONLY the two build outputs
  Say "`n[1/4] Cleaning build outputs (only the two EXEs)"
  Remove-FileIfExists $backendExe
  if (Test-Path $electronDist) {
    $oldElectronExes = Get-ChildItem -LiteralPath $electronDist -Filter $ElectronExeGlob -File -ErrorAction SilentlyContinue
    if ($oldElectronExes) {
      foreach ($f in $oldElectronExes) { Remove-FileIfExists $f.FullName }
    } else {
      Say "   (skip) No $ElectronExeGlob found in $electronDist"
    }
  } else {
    Say "   (skip) No electron dist folder yet: $electronDist"
  }

  # 2) Python deps
  if (-not $SkipInstall) {
    Say "`n[2/4] Ensuring Python deps"
    Do "python" @("-m","pip","install","--upgrade","pip","setuptools","wheel")
    Do "python" @("-m","pip","install","flask","pyinstaller")
  } else {
    Say "`n[2/4] Skipping Python installs (--SkipInstall)"
  }

  # 3) Build backend exe
  Say "`n[3/4] Building backend with PyInstaller"
  $pyiArgs = @(
    "-m","PyInstaller",
    "app.py",
    "--onefile",
    "--add-data","templates;templates",
    "--add-data","static;static",
    "--name","projecttracker-backend"
  )
  Do "python" $pyiArgs

  if (-not $DryRun) {
    if (-not (Test-Path $backendExe)) { throw "PyInstaller output missing: $backendExe" }
    Say "   Built: $backendExe"
  } else {
    Say "   (dry-run) Would verify: $backendExe"
  }

  # 4) Package Electron
  Say "`n[4/4] Packaging Electron app"
  Push-Location $electronDir
  try {
    if (-not $SkipInstall) {
      # Allow npm.ps1 in locked environments
      if (-not $DryRun) { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force | Out-Null }
      if (Test-Path ".\package-lock.json") { Do "npm" @("ci") } else { Do "npm" @("install") }
    } else {
      Say "   Skipping npm install (--SkipInstall)"
    }

    # Ensure no stale EXEs right before packaging (again, just the EXEs)
    if (Test-Path $electronDist) {
      $oldElectronExes = Get-ChildItem -LiteralPath $electronDist -Filter $ElectronExeGlob -File -ErrorAction SilentlyContinue
      foreach ($f in $oldElectronExes) { Remove-FileIfExists $f.FullName }
    }

    Do "npm" @("run","dist")

    if (-not $DryRun) {
      $newExe = Get-ChildItem -LiteralPath $electronDist -Filter $ElectronExeGlob -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
      if ($newExe) {
        Say "   Electron EXE: $($newExe.FullName)"
      } else {
        Say "   WARNING: Electron EXE not found in $electronDist"
      }
    } else {
      Say "   (dry-run) Would locate $ElectronExeGlob in $electronDist"
    }
  } finally {
    Pop-Location
  }

  Say "`nDone."
}
finally {
  Pop-Location
}
