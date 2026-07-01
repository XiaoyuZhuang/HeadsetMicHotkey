# HeadsetMicHotkey

A tiny Windows tray utility that maps a headset play/pause button to a configurable hotkey. It was built for voice input workflows where an inline headset microphone is close to your mouth, and the headset button becomes a quick dictation trigger.

By default, the app maps the headset play/pause button to `Left Shift + Z`.

## Features

- Runs quietly in the Windows system tray
- Maps the headset play/pause media key to a configurable hotkey
- Keeps the audio endpoint awake with a quiet audio keep-alive loop
- Supports startup installation and removal
- Stores logs next to the app for easy debugging
- Uses a portable folder layout, so the app can be moved between machines
- Includes tray menu actions for pause/resume, test hotkey, config, logs, and exit

## Quick Start

1. Download or clone this repository.
2. Open the `HeadsetButtonHotkey` folder.
3. Double-click `start-headset-button-hotkey.cmd`.
4. Use the tray icon to pause, test, open config, open logs, or exit.

To see console output while testing, run:

```powershell
HeadsetButtonHotkey\start-headset-button-hotkey-visible.cmd
```

## Startup

Install startup for the current Windows user:

```powershell
HeadsetButtonHotkey\install-startup.cmd
```

Remove startup:

```powershell
HeadsetButtonHotkey\uninstall-startup.cmd
```

The startup shortcut points to the current folder, so if you move the app later, run `install-startup.cmd` again from the new location.

## Configuration

Edit:

```text
HeadsetButtonHotkey\headset-button-config.json
```

Default configuration:

```json
{
  "enabled": true,
  "targetHotkey": {
    "modifier": "LShift",
    "key": "Z"
  },
  "timing": {
    "holdMs": 140,
    "cooldownMs": 500,
    "preSendDelayMs": 120
  },
  "audioKeepAlive": {
    "enabled": true,
    "waveFrequencyHz": 220,
    "waveSeconds": 5
  },
  "statusSound": {
    "enabled": true
  },
  "logging": {
    "enabled": true,
    "directory": "logs"
  },
  "tray": {
    "enabled": true,
    "showBalloonOnStart": true
  }
}
```

Supported modifier names include `LShift`, `RShift`, `Shift`, `LCtrl`, `RCtrl`, `Ctrl`, `LAlt`, `RAlt`, and `Alt`.

Single letter keys such as `Z`, `A`, or `K` are supported.

## Logs

Logs are written to:

```text
HeadsetButtonHotkey\logs
```

The log folder is intentionally ignored by Git.

## Why Audio Keep-Alive Exists

Some 3.5mm inline headset buttons do not behave like always-on keyboard devices. On certain Windows audio drivers, the play/pause button only becomes reliable after an audio session wakes the headset/audio endpoint.

This utility can loop a very quiet generated WAV file in the background to keep that path active. If your headset button works without it, set:

```json
"audioKeepAlive": {
  "enabled": false
}
```

## Troubleshooting

If the tray app is running but the button does nothing:

- Make sure no older debug or visible window version is running at the same time.
- Right-click the tray icon and choose `Test hotkey`.
- Open the log folder from the tray menu and check the latest log file.
- Try running `start-headset-button-hotkey-visible.cmd` to see live output.
- If the target app is running as administrator, run this utility as administrator too.

Debug helpers are available in the `tools` folder.

## Requirements

- Windows
- PowerShell
- .NET Framework assemblies available on standard Windows installations

No external dependencies are required.

## License

MIT
