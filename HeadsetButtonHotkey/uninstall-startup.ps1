$ErrorActionPreference = "Stop"

$startupDir = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir "Headset Button Hotkey.lnk"

if (Test-Path -LiteralPath $shortcutPath) {
    Remove-Item -LiteralPath $shortcutPath
    Write-Host "Startup shortcut removed:"
    Write-Host $shortcutPath
} else {
    Write-Host "Startup shortcut was not installed."
}
