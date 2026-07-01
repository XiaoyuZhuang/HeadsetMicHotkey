@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0diagnose-headset-button.ps1" -HoldMs 180 -CooldownMs 500
