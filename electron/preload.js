const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  chooseDataDir: () => ipcRenderer.invoke('choose-data-dir'),
});
