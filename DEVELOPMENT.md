# Development

HeadsetMicHotkey v2 is intentionally small and dependency-light.

## Current stack

- C#
- Windows Forms
- .NET Framework 4.8
- Win32 low-level keyboard hook
- Win32 keyboard injection

The GUI source is under `HeadsetMicHotkeyV2/`.

## Project layout

```text
HeadsetMicHotkeyV2/
├─ HeadsetMicHotkey.csproj
├─ Program.cs
└─ generate-icon.ps1
```

`Program.cs` currently contains the application lifecycle, tray integration, GUI, settings, keyboard hook, shortcut sender, audio keep-alive, logging and Win32 interop code. The project is kept compact on purpose because this is a small Windows utility.

## Automatic build

Normal users do not need a development environment.

Every relevant change on `main` runs the GitHub Actions Windows build. The workflow:

1. Checks out the repository.
2. Generates the AI + microphone application icon.
3. Restores and builds the .NET Framework 4.8 project in Release mode.
4. Uploads the EXE as a workflow artifact.
5. Publishes the latest compiled executable to `dist/HeadsetMicHotkey.exe`.

The `dist` EXE is therefore the recommended download exposed by the README.

## Local build

If local compilation is needed, use a Windows machine with Visual Studio / MSBuild and the .NET Framework 4.8 targeting pack.

Generate the icon first:

```powershell
powershell -ExecutionPolicy Bypass -File .\HeadsetMicHotkeyV2\generate-icon.ps1
```

Then build:

```powershell
msbuild .\HeadsetMicHotkeyV2\HeadsetMicHotkey.csproj /t:Restore /p:Configuration=Release
msbuild .\HeadsetMicHotkeyV2\HeadsetMicHotkey.csproj /p:Configuration=Release
```

Expected output:

```text
HeadsetMicHotkeyV2\bin\Release\net48\HeadsetMicHotkey.exe
```

## Runtime data

User settings and generated runtime data are intentionally kept outside the executable:

```text
%LocalAppData%\HeadsetMicHotkey\
```

This allows users to replace the EXE during an update without normally losing their configuration.

## Legacy implementation

The original CMD/PowerShell implementation is preserved under `HeadsetButtonHotkey/`. New feature work should target the native GUI implementation instead.
