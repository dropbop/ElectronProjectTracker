# ProjectTracker

This is an app for tracking projects and tasks associated with them. It also includes an Anki-style flashcard system. It's built using Flask + HTML/CSS with an Electron wrapper to run as a desktop app. Data is stored in plain JSON files on your machine.

---

## What's in here

- **Flask backend** (`app.py`, `templates/`, `static/`)
- **Electron wrapper** (`electron/`) that spawns the backend and opens a desktop window
- **Data files** live wherever you choose (default: your Documents folder when using the Electron app; configurable)
- **Build automation** (`build-app.ps1`, `build-app.bat`) for one-click builds

`.gitignore` excludes local Python installs, PyInstaller output, and Electron build output.

---

## Quick Start (Windows / PowerShell)

You need:
- **Python 3.11+** (3.13 works)
- **Node.js (LTS)** for Electron (`node -v` / `npm -v` should print versions)

### Automated Build (Recommended)

Simply **double-click `build-app.bat`** in the repo root. This will:
1. Clean up any previous builds
2. Install/update Python dependencies
3. Build the Flask backend into an exe
4. Package everything with Electron
5. Show you where the final installer is located

The script provides colored output and clear error messages if anything goes wrong.

**Optional build flags:**
- Run PowerShell directly for more control: `.\build-app.ps1 -SkipCleanup -Verbose`
  - `-SkipCleanup` - Don't delete previous builds
  - `-SkipPipUpgrade` - Skip pip upgrade (faster if packages are current)
  - `-Verbose` - Show detailed PyInstaller output

---

## Manual Build Process

If you prefer to build manually or need to debug, here are the individual steps:

**Run everything below from the repo root** 

### 1) Build the backend EXE (PyInstaller)

Install deps **into this repo** (no `--user`, no venv required):

    python -m pip install --upgrade pip setuptools wheel
    python -m pip install flask pyinstaller

Build the single-file backend EXE (bundles templates/static):

    python -m PyInstaller src/app.py --onefile --add-data "templates;templates" --add-data "static;static" --name projecttracker-backend

Result: `dist\projecttracker-backend.exe`

**(Optional) Quick test (backend only):**

    $env:PROJECTTRACKER_DATA_DIR = "$env:USERPROFILE\Documents\ProjectTrackerData"
    $env:PROJECTTRACKER_PORT = "5000"   # optional; 0 chooses a free port
    .\dist\projecttracker-backend.exe
    # Open http://127.0.0.1:5000 in a browser. Ctrl+C to stop.

### 2) Build the desktop app (Electron)

From the repo root:

    cd .\electron\
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    
    npm install
    npm run dist

Result: `electron\dist\projecttracker-electron Portable.exe`  
Double-click it. Use the **"Data Folder"** button in the title bar to pick where your JSON files should live.

> Electron's build config copies `..\dist\projecttracker-backend.exe` via `extraResources`. Make sure you completed step 1 before `npm run dist`.

---

## Developer Workflow

### Quick rebuild
Just double-click `build-app.bat` for a complete rebuild.

### Manual rebuilds
- **Change Python/HTML/CSS → rebuild backend:**

      # repo root
      python -m PyInstaller src/app.py --onefile --add-data "templates;templates" --add-data "static;static" --name projecttracker-backend

- **Change Electron code → rebuild Electron:**

      cd .\electron\
      npm run dist

- **Optional dev run for Electron (uses your system Python to start src/app.py):**

      cd .\electron\
      npm start

---

## Where your data lives

- **Electron app**: defaults to your **Documents** folder; change it via the **Data Folder** button (persisted by the app).
- **Direct backend run**: set `PROJECTTRACKER_DATA_DIR` (see above).
- Files created:
  - `project_data.json` (projects/tasks)
  - `anki.json` (flashcards)

---

## Releasing a build

1. Bump version in `electron/package.json` (`"version": "x.y.z"`).
2. Rebuild using the automated script:

       # Just double-click build-app.bat
       # OR run from PowerShell:
       .\build-app.ps1

3. Test `electron\dist\projecttracker-electron Portable.exe`.
4. Create a GitHub Release and upload the EXE as an asset (optionally attach checksums).
