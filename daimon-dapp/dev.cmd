@echo off
rem Avvia il dev server con il Node portable nel PATH (vedi README).
set "PATH=C:\Users\Utente\.node\node-v22.12.0-win-x64;%PATH%"
cd /d "%~dp0"
npm run dev
