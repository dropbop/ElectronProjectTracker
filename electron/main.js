const { app, BrowserWindow, ipcMain, dialog } = require('electron');
const path = require('path');
const { spawn } = require('child_process');
const Store = require('electron-store');
const getPort = require('get-port');

const store = new Store();
let backend;
let currentPort;

async function startBackend() {
  currentPort = await getPort();
  const dataDir = store.get('dataDir') || app.getPath('documents');
  const env = {
    ...process.env,
    PROJECTTRACKER_PORT: String(currentPort),
    PROJECTTRACKER_DATA_DIR: dataDir,
  };
  if (app.isPackaged) {
    const exe = path.join(process.resourcesPath, 'projecttracker-backend.exe');
    backend = spawn(exe, [], { env });
  } else {
    const script = path.join(__dirname, '..', 'app.py');
    const python = process.platform === 'win32' ? 'python' : 'python3';
    backend = spawn(python, [script], { env });
  }
  backend.on('exit', (code) => {
    console.log('Backend exited', code);
  });
  await waitForHealth();
}

async function waitForHealth() {
  const url = `http://127.0.0.1:${currentPort}/__health`;
  for (let i = 0; i < 50; i++) {
    try {
      const res = await fetch(url);
      if (res.ok) return;
    } catch (e) {
      // ignore
    }
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error('Backend failed to start');
}

async function createWindow() {
  await startBackend();
  const win = new BrowserWindow({
    webPreferences: { preload: path.join(__dirname, 'preload.js') },
  });
  win.loadURL(`http://127.0.0.1:${currentPort}`);
}

app.whenReady().then(createWindow);

app.on('before-quit', () => {
  if (backend) backend.kill();
});

ipcMain.handle('choose-data-dir', async () => {
  const { canceled, filePaths } = await dialog.showOpenDialog({
    properties: ['openDirectory'],
  });
  if (!canceled && filePaths[0]) {
    store.set('dataDir', filePaths[0]);
  }
  return store.get('dataDir');
});
