# Changelog

## v2.0.1 — 2026-09-10

This is the first recommended native GUI release.

### Added

- Native Windows GUI executable
- System tray lifecycle with reopen / pause / test / logs / exit actions
- Custom hotkey recording from the keyboard
- Support for Ctrl, Shift, Alt and Windows-key combinations
- Support for single-key targets such as F8 and Space
- One-click Windows startup option
- Audio keep-alive controls
- Automatic settings persistence under `%LocalAppData%\HeadsetMicHotkey`
- Light/dark appearance handling
- Single-instance protection
- AI + microphone application icon
- GitHub Actions Windows build
- Automatically published `dist/HeadsetMicHotkey.exe`

### Fixed

- Corrected the Win32 `INPUT` / `SendInput` structure used by the 64-bit process
- Added keyboard-injection fallback behavior
- Added more useful injection diagnostics to the log
- Fixed controls and activity text being clipped in the main window
- Separated headset detection from successful hotkey-send status in the UI

### Changed

- Normal use no longer requires CMD, PowerShell, or manual JSON editing
- Closing the main window now leaves the application running only in the Windows notification area
- The original script implementation is retained under `HeadsetButtonHotkey/` as a legacy/reference version

## v1.x — legacy script version

The original implementation used CMD/PowerShell as the launcher/runtime shell and dynamically hosted the tray utility. It remains in the repository for reference but is no longer the recommended version.
