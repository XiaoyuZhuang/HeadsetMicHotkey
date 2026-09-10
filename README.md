# HeadsetMicHotkey

[中文说明](README.zh-CN.md) | English

A tiny native Windows utility that maps a headset play/pause button to a customizable keyboard shortcut. It was originally built for voice-input workflows, so an inline headset button can become a fast dictation trigger.

The current recommended version is **v2.0.1**. It is now a real Windows GUI application: no CMD window, no PowerShell host, no minimized console window, and no manual config editing for normal use.

## Download

**Recommended:** download the latest compiled EXE directly from the repository:

[Download HeadsetMicHotkey.exe](dist/HeadsetMicHotkey.exe?raw=1)

No installer is required. Just download the EXE and run it.

> Windows may show an "Unknown publisher" / SmartScreen warning because the executable is not code-signed with a commercial certificate.

## What changed in v2

- Native Windows GUI application
- Runs as a real `WinExe` with no console window
- Minimizes to the Windows notification area / system tray
- Double-click the tray icon to reopen the main window
- Single-instance protection to avoid duplicate keyboard hooks
- Record a custom shortcut directly from the keyboard
- Supports Ctrl / Shift / Alt / Win combinations and single keys such as F8
- Built-in `Test` action for the selected shortcut
- Configurable audio keep-alive
- One-click startup toggle
- Settings stored automatically under `%LocalAppData%\HeadsetMicHotkey`
- Automatic light/dark appearance support
- AI + microphone application icon
- Diagnostic logging and keyboard-injection fallback handling
- Very small executable because it targets the .NET Framework already available on standard modern Windows installations

The default mapping remains:

```text
Headset Play / Pause  ->  Shift + Z
```

## Quick start

1. Download `HeadsetMicHotkey.exe` from the link above.
2. Double-click it.
3. Click **Record new hotkey** if you want to change the default `Shift + Z` mapping.
4. Press the headset play/pause button.
5. Close the main window when you are done configuring it; the app keeps running in the system tray.

The main window contains the controls most people need:

- **Mapping** — enable or pause the headset-button mapping
- **Audio keep-alive** — keep compatible headset/audio endpoints awake
- **Run at startup** — start the app automatically with Windows
- **Record new hotkey** — capture a new keyboard shortcut
- **Test** — send the configured shortcut without using the headset button
- **Advanced** — timing and keep-alive options

## Custom shortcuts

The GUI records shortcuts directly. You do not need to edit JSON manually.

Examples include:

```text
Shift + Z
Ctrl + Shift + M
Ctrl + Alt + Space
Win + Shift + S
F8
Space
```

The shortcut is saved automatically and restored the next time the app starts.

## System tray behavior

Closing the main window does **not** exit the app. It hides the window and leaves the application running in the Windows notification area.

From the tray icon you can:

- Open the main window
- Pause / enable mapping
- Test the current shortcut
- Open the log folder
- Exit completely

## Audio keep-alive

Some 3.5 mm inline headset buttons are not exposed as always-active keyboard devices. On some audio drivers the play/pause button becomes more reliable while an audio session keeps the endpoint awake.

HeadsetMicHotkey can generate and loop a very quiet WAV signal in the background. If your headset works reliably without it, turn **Audio keep-alive** off in the main window.

## Settings and logs

Application data is stored outside the EXE, so replacing the executable with a newer version does not normally reset your settings.

```text
%LocalAppData%\HeadsetMicHotkey\
```

Logs are stored in:

```text
%LocalAppData%\HeadsetMicHotkey\logs\
```

The log records headset detection and shortcut injection attempts, which makes it useful for troubleshooting.

## Troubleshooting

If the headset button is detected but the target application does not react:

1. Use **Test** first. If Test works, the output shortcut path is fine and the issue is likely related to headset input handling.
2. Open the log folder from the tray menu and inspect the newest log.
3. Confirm the shortcut works when pressed manually in the target application.
4. If the target application runs elevated, try running HeadsetMicHotkey with the same privilege level.
5. Make sure an older copy of HeadsetMicHotkey is not still running.

v2.0.1 includes corrected Win32 `SendInput` structures plus a compatibility fallback for keyboard injection.

## Build from source

Most users do **not** need to compile anything. GitHub Actions builds the Windows EXE automatically.

Source code for the current GUI version is in:

```text
HeadsetMicHotkeyV2/
```

The application targets .NET Framework 4.8 and Windows Forms. If you do want to build locally, open the project in Visual Studio / MSBuild and build the `Release` configuration.

The repository workflow also regenerates the application icon and produces the compiled EXE automatically.

## Legacy version

The original PowerShell/CMD implementation is kept under:

```text
HeadsetButtonHotkey/
```

It is preserved for reference and troubleshooting, but the native GUI EXE is now the recommended version.

## License

MIT
