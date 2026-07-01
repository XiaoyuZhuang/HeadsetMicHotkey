$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$target = Join-Path $scriptDir "start-headset-button-hotkey.cmd"
$startupDir = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir "Headset Button Hotkey.lnk"

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $target
$shortcut.WorkingDirectory = $scriptDir
$shortcut.WindowStyle = 7
$shortcut.Description = "Headset play/pause button to configured hotkey"
$shortcut.Save()

Write-Host "Startup shortcut installed:"
Write-Host $shortcutPath
