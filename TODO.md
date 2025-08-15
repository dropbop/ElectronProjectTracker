# ProjectTracker — TODO List

Format: Number • Type • Details • (Optional) Code Snippet

---

1) **Bug — Anki reverse-card overwrite & duplicates**  
Details: Updating a card can overwrite or desync its reverse, and reverse clones show up in the manager; add an `is_reverse` flag, keep reverse cards out of the list, and update/create/delete the reverse within the same in-memory `data` before a single save.  
```python
# In anki.py (concept):
new_card = {"reverse": reverse, "is_reverse": False, ...}
reverse_card = {"reverse": False, "is_reverse": True, ...}
# In edit_anki.html, list only primary cards:
{% if not card.get('is_reverse', False) %} ... {% endif %}
```

2) **Bug — Nested forms in `edit_project.html`**  
Details: A main `<form>` wraps the page and inner `<form>` tags are rendered per update; nested forms are invalid and cause flaky submits—use detached forms plus the `form` attribute on the delete button.  
```html
<!-- Button inside main form -->
<button type="submit" class="primary-button" form="del-{{ update.id }}">DELETE</button>
<!-- Standalone (outside main form) -->
<form id="del-{{ update.id }}" method="post"
      action="{{ url_for('delete_update', project_id=project.id, update_id=update.id) }}"></form>
```

3) **Bug — Task status sort mapping uses project statuses**  
Details: The template maps `status` using project values; tasks use `active/on hold/completed/cancelled`; fix the mapping so sorting is correct.  
```jinja
{% set status_order = {'active': 0, 'on hold': 1, 'completed': 2, 'cancelled': 3} %}
```

4) **QuickFix — Make “Data Folder” button tell users to restart**  
Details: Changing the data dir only affects the next backend spawn; add an alert after selection so users know to restart.  
```html
<a href="#" class="control-button"
   onclick="window.api?.chooseDataDir?.().then(p=>alert(`Data folder set to:\n${p}\n\nRestart the app to apply.`)); return false;">
  DATA FOLDER
</a>
```

5) **Suggestion — Auto-restart backend when data dir changes**  
Details: After choosing a new folder, kill and respawn the backend child process with updated env, or relaunch the app; this removes the manual restart step.  
```js
// main.js (concept): after chooseDataDir, backend.kill(); await startBackend(); win.loadURL(...)
```

6) **Suggestion — Stronger Flask secret key handling**  
Details: Don’t ship with `your_default_secret_key`; in packaged builds, require an env var or generate and persist one via `electron-store`; abort startup if missing in dev.  
```python
# app.py
key = os.environ.get("FLASK_SECRET_KEY")
if not key and getattr(sys, "frozen", False):
    raise RuntimeError("FLASK_SECRET_KEY required in packaged app")
app.secret_key = key or "dev-only-not-secret"
```

7) **Suggestion — Optional rotating backups in `safe_io.atomic_write_json`**  
Details: Before `os.replace`, write a timestamped or `.bak` copy of the current file and keep the last N to make recovery easy even if a sync client corrupts the file.  
```python
from shutil import copy2
if os.path.exists(path):
    copy2(path, path + ".bak")
# then os.replace(tmp_path, path)
```

8) **Suggestion — Surface JSON decode errors and guard writes**  
Details: Returning empty data on `JSONDecodeError` risks accidental data loss; surface a UI banner and block writes until the user fixes/restores the file.  
```python
# data_handler.load_data()
try: return json.load(file)
except json.JSONDecodeError as e:
    raise RuntimeError(f"Corrupt JSON at {DATA_FILE}: {e}")
```

9) **QuickFix — Add `requirements.txt` for reproducible builds**  
Details: Pin Flask and PyInstaller versions known to work; this reduces “works on my machine” drift.  
```txt
# requirements.txt
Flask==3.0.*
PyInstaller==6.10.*
```

10) **QuickFix — Electron lifecycle: quit app when window closed**  
Details: On Windows, closing the window should quit and kill the backend; add a `window-all-closed` handler.  
```js
app.on('window-all-closed', () => { app.quit(); });
```

11) **Suggestion — Centralize and validate status vocab**  
Details: Define canonical status sets for projects and tasks in one place, validate inputs server-side, and document them in the README to prevent drift.  
```python
PROJECT_STATUSES = {'active','on hold','complete','archived','ongoing'}
TASK_STATUSES = {'active','on hold','completed','cancelled'}
```

12) **Suggestion — Unit tests for SM2 and safe I/O**  
Details: Add small tests for SM2 interval/EF updates and for `atomic_write_json` retry path (simulate lock) to catch regressions early.

13) **Suggestion — Basic logging for backend & spawn errors**  
Details: Log Electron spawn stdout/stderr to a file in the data folder and show a dialog if the health check fails so users can report actionable errors.  
```js
backend = spawn(exe, [], { env });
backend.stdout.on('data', b => appendFileSync(logPath, b));
backend.stderr.on('data', b => appendFileSync(logPath, b));
```

14) **Suggestion — Harden date handling and sentinels**  
Details: Replace `'9999-12-31'` with `None` in data and handle display in the template to avoid accidental comparisons and odd sorting edge cases; parse/validate dates on write.  
```python
# Store None; in sort, use (date or '9999-12-31') only for comparison
```

15) **Suggestion — README touch-ups (small but useful)**  
Details: Document status enums, default data dir behavior, dev vs packaged runs, ExecutionPolicy troubleshooting, and exact Node/Electron versions used by `electron-builder` for clarity.

---

**That’s it.** Knock out 1–4 first; the rest are low friction polish that will pay off over time.
