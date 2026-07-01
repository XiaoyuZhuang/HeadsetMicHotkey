@echo off
cd /d "%~dp0"
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "%~dp0headset-button-to-shift-z.ps1"
