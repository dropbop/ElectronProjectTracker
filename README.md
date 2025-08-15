# ProjectTracker
This is a Flask + HTML + CSS CRUD app for project tracking. It writes to a JSON "database" and is meant to be run 100% locally.

## Running the backend directly
Set a data directory and optional port via environment variables:

```
set PROJECTTRACKER_DATA_DIR=C:\path\to\data
set PROJECTTRACKER_PORT=5000
python app.py
```

## Electron desktop build
The `electron/` folder contains a minimal Electron wrapper that spawns the
Flask backend and loads it in a desktop window. The backend is packaged with
PyInstaller and shipped as a single executable.

Build steps:

1. Create the backend binary:
   ```
   pyinstaller app.py --onefile --add-data "templates;templates" --add-data "static;static" --name projecttracker-backend
   ```
   The resulting `dist/projecttracker-backend.exe` is referenced by the Electron config.
2. From the `electron` directory install dependencies and build:
   ```
   npm install
   npm run dist
   ```
   This produces a portable Windows executable that can run from a USB drive.
