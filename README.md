# ProjectTracker

Flask + HTML/CSS CRUD app for tracking projects and tasks. Data is stored in plain JSON files on your machine. Includes a minimal Electron wrapper to run it as a desktop app.

---

## What’s in here

- **Flask backend** (`app.py`, `templates/`, `static/`)
- **Electron wrapper** (`electron/`) that spawns the backend and opens a desktop window
- **Data files** live wherever you choose (default: your Documents folder when using the Electron app; configurable)

`.gitignore` excludes local Python installs, PyInstaller output, and Electron build output.

---

## Quick Start (Windows / PowerShell)

You need:
- **Python 3.11+** (3.13 works)
- **Node.js (LTS)** for Electron (`node -v` / `npm -v` should print versions)

**Run everything below from the repo root** (folder with `app.py` and the `electron/` folder).

### 1) Build the backend EXE (PyInstaller)

Install deps **into this repo** (no `--user`, no venv required):

    python -m pip install --upgrade pip setuptools wheel
    python -m pip install flask pyinstaller

Build the single-file backend EXE (bundles templates/static):

    python -m PyInstaller app.py --onefile --add-data "templates;templates" --add-data "static;static" --name projecttracker-backend

Result: `dist\projecttracker-backend.exe`

**(Optional) Quick test (backend only):**

    $env:PROJECTTRACKER_DATA_DIR = "$env:USERPROFILE\Documents\ProjectTrackerData"
    $env:PROJECTTRACKER_PORT = "5000"   # optional; 0 chooses a free port
    .\dist\projecttracker-backend.exe
    # Open http://127.0.0.1:5000 in a browser. Ctrl+C to stop.

### 2) Build the desktop app (Electron)

From the repo root:

    cd .\electron\
    npm install
    npm run dist

Result: `electron\dist\projecttracker-electron Portable.exe`  
Double-click it. Use the **“Data Folder”** button in the title bar to pick where your JSON files should live.

> Electron’s build config copies `..\dist\projecttracker-backend.exe` via `extraResources`. Make sure you completed step 1 before `npm run dist`.

---

## Developer Workflow

- **Change Python/HTML/CSS → rebuild backend:**

      # repo root
      python -m PyInstaller app.py --onefile --add-data "templates;templates" --add-data "static;static" --name projecttracker-backend

- **Change Electron code → rebuild Electron:**

      cd .\electron\
      npm run dist

- **Optional dev run for Electron (uses your system Python to start app.py):**

      cd .\electron\
      npm start

---

## Running the backend directly (no Electron)

PowerShell:

    $env:PROJECTTRACKER_DATA_DIR = "C:\path\to\data"
    $env:PROJECTTRACKER_PORT = "5000"   # optional; 0 chooses a free port
    python .\app.py

CMD equivalents:

    set PROJECTTRACKER_DATA_DIR=C:\path\to\data
    set PROJECTTRACKER_PORT=5000
    python app.py

Browse to `http://127.0.0.1:5000`.

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
2. Rebuild:

       # repo root
       python -m PyInstaller app.py --onefile --add-data "templates;templates" --add-data "static;static" --name projecttracker-backend
       cd .\electron\
       npm install
       npm run dist

3. Test `electron\dist\projecttracker-electron Portable.exe`.
4. Create a GitHub Release and upload the EXE as an asset (optionally attach checksums).

---

## Troubleshooting

- **`No module named pyinstaller` when building**  
  You installed deps somewhere else. Run installs **from the repo root**, without `--user`:

      python -m pip install flask pyinstaller

  Then build with `python -m PyInstaller ...`.

- **“Could not find platform independent libraries <prefix>”**  
  Cosmetic message with some Windows Python installs. Safe to ignore.

- **Electron build can’t find the backend EXE**  
  Ensure `dist\projecttracker-backend.exe` exists **one level above** `electron\` (do step 1 first).

- **Port in use** (manual test)  
  Set a different `PROJECTTRACKER_PORT`.

---

## Tech notes

- Electron versions are pinned in `electron/package.json` (`electron@^28`, `electron-builder@^24`).
- The backend locates packaged templates/static using `_MEIPASS` (PyInstaller temp folder) so the single-file EXE works.
- `.gitignore` excludes `build/`, `dist/`, Electron build output, and local Python folders; keep `dist/` on disk locally so Electron can bundle the backend EXE, but don’t commit it.
