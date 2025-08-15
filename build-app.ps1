# Flask to Electron Build Automation Script
# This script automates the process of building a Flask app into an exe and packaging it with Electron

param(
    [switch]$SkipCleanup = $false,
    [switch]$SkipPipUpgrade = $false,
    [switch]$Verbose = $false
)

# Get the script's directory (where this .ps1 file lives)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

# Define paths
$distPythonPath = Join-Path $scriptDir "dist"
$electronPath = Join-Path $scriptDir "electron"
$electronDistPath = Join-Path $electronPath "dist"
$backendExePath = Join-Path $distPythonPath "projecttracker-backend.exe"

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Function to handle errors
function Handle-Error {
    param(
        [string]$ErrorMessage
    )
    Write-ColorOutput "ERROR: $ErrorMessage" "Red"
    Write-ColorOutput "Press any key to exit..." "Yellow"
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Start of script
Write-ColorOutput "`n=== Flask to Electron Build Automation ===" "Cyan"
Write-ColorOutput "Working directory: $scriptDir" "Gray"

# Step 1: Clean up old builds
if (-not $SkipCleanup) {
    Write-ColorOutput "`n[1/5] Cleaning up old builds..." "Yellow"
    
    # Clean Python dist
    if (Test-Path $distPythonPath) {
        Write-ColorOutput "  - Removing old Python dist folder..." "Gray"
        try {
            Remove-Item -Path $distPythonPath -Recurse -Force -ErrorAction Stop
            Write-ColorOutput "  ✓ Python dist cleaned" "Green"
        } catch {
            Write-ColorOutput "  ! Warning: Could not fully clean Python dist: $_" "Yellow"
        }
    }
    
    # Clean Python build folder if it exists
    $buildPath = Join-Path $scriptDir "build"
    if (Test-Path $buildPath) {
        Write-ColorOutput "  - Removing Python build folder..." "Gray"
        Remove-Item -Path $buildPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Clean .spec file if it exists
    $specFile = Join-Path $scriptDir "*.spec"
    if (Test-Path $specFile) {
        Write-ColorOutput "  - Removing .spec files..." "Gray"
        Remove-Item -Path $specFile -Force -ErrorAction SilentlyContinue
    }
    
    # Clean Electron dist
    if (Test-Path $electronDistPath) {
        Write-ColorOutput "  - Removing old Electron dist folder..." "Gray"
        try {
            Remove-Item -Path $electronDistPath -Recurse -Force -ErrorAction Stop
            Write-ColorOutput "  ✓ Electron dist cleaned" "Green"
        } catch {
            Write-ColorOutput "  ! Warning: Could not fully clean Electron dist: $_" "Yellow"
        }
    }
} else {
    Write-ColorOutput "`n[1/5] Skipping cleanup (flag set)" "Gray"
}

# Step 2: Prepare Python environment
Write-ColorOutput "`n[2/5] Preparing Python environment..." "Yellow"

if (-not $SkipPipUpgrade) {
    Write-ColorOutput "  - Upgrading pip, setuptools, and wheel..." "Gray"
    & python -m pip install --upgrade pip setuptools wheel --quiet
    if ($LASTEXITCODE -ne 0) {
        Handle-Error "Failed to upgrade pip/setuptools/wheel"
    }
}

Write-ColorOutput "  - Installing/upgrading Flask and PyInstaller..." "Gray"
& python -m pip install --upgrade flask pyinstaller --quiet
if ($LASTEXITCODE -ne 0) {
    Handle-Error "Failed to install Flask/PyInstaller"
}
Write-ColorOutput "  ✓ Python environment ready" "Green"

# Step 3: Build Flask application with PyInstaller
Write-ColorOutput "`n[3/5] Building Flask application with PyInstaller..." "Yellow"

# Check if app.py exists
$appPyPath = Join-Path $scriptDir "app.py"
if (-not (Test-Path $appPyPath)) {
    Handle-Error "app.py not found in $scriptDir"
}

# Check if templates and static folders exist
$templatesPath = Join-Path $scriptDir "templates"
$staticPath = Join-Path $scriptDir "static"
$addDataArgs = @()

if (Test-Path $templatesPath) {
    $addDataArgs += "--add-data", "templates;templates"
    Write-ColorOutput "  - Including templates folder" "Gray"
}

if (Test-Path $staticPath) {
    $addDataArgs += "--add-data", "static;static"
    Write-ColorOutput "  - Including static folder" "Gray"
}

Write-ColorOutput "  - Running PyInstaller..." "Gray"
$pyInstallerArgs = @(
    "-m", "PyInstaller",
    "app.py",
    "--onefile",
    "--name", "projecttracker-backend"
)

if ($addDataArgs.Count -gt 0) {
    $pyInstallerArgs += $addDataArgs
}

if (-not $Verbose) {
    $pyInstallerArgs += "--log-level", "WARN"
}

& python $pyInstallerArgs
if ($LASTEXITCODE -ne 0) {
    Handle-Error "PyInstaller build failed"
}

# Verify the exe was created
if (-not (Test-Path $backendExePath)) {
    Handle-Error "Backend exe was not created at $backendExePath"
}

Write-ColorOutput "  ✓ Flask app built successfully" "Green"
Write-ColorOutput "    Output: $backendExePath" "Gray"

# Step 4: Change to Electron directory and install dependencies
Write-ColorOutput "`n[4/5] Preparing Electron environment..." "Yellow"

if (-not (Test-Path $electronPath)) {
    Handle-Error "Electron folder not found at $electronPath"
}

Set-Location $electronPath
Write-ColorOutput "  - Changed to Electron directory" "Gray"

# Check if package.json exists
if (-not (Test-Path "package.json")) {
    Handle-Error "package.json not found in Electron folder"
}

Write-ColorOutput "  - Installing npm dependencies..." "Gray"
& npm install
if ($LASTEXITCODE -ne 0) {
    Handle-Error "npm install failed"
}
Write-ColorOutput "  ✓ Electron dependencies installed" "Green"

# Step 5: Build Electron application
Write-ColorOutput "`n[5/5] Building Electron application..." "Yellow"

# Copy the backend exe to electron folder if needed
$electronBackendPath = Join-Path $electronPath "projecttracker-backend.exe"
if (Test-Path $backendExePath) {
    Write-ColorOutput "  - Copying backend exe to Electron folder..." "Gray"
    Copy-Item -Path $backendExePath -Destination $electronBackendPath -Force
}

Write-ColorOutput "  - Running Electron builder..." "Gray"
& npm run dist
if ($LASTEXITCODE -ne 0) {
    Handle-Error "Electron build failed"
}

# Find the created installer
$installerPattern = Join-Path $electronDistPath "*.exe"
$installer = Get-ChildItem -Path $installerPattern -ErrorAction SilentlyContinue | Select-Object -First 1

if ($installer) {
    Write-ColorOutput "  ✓ Electron app built successfully" "Green"
    Write-ColorOutput "    Output: $($installer.FullName)" "Gray"
} else {
    Write-ColorOutput "  ! Warning: Could not find installer in $electronDistPath" "Yellow"
    Write-ColorOutput "    Check the dist folder manually" "Gray"
}

# Return to original directory
Set-Location $scriptDir

# Success message
Write-ColorOutput "`n=== Build Complete ===" "Cyan"
Write-ColorOutput "Flask backend: $backendExePath" "Green"
if ($installer) {
    Write-ColorOutput "Electron app: $($installer.FullName)" "Green"
}

Write-ColorOutput "`nPress any key to exit..." "Gray"
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
