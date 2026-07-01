param(
    [switch]$Test,
    [string]$ConfigPath = "$PSScriptRoot\headset-button-config.json",
    [switch]$NoAudioKeepAlive
)

Set-StrictMode -Version 2.0

function New-DefaultConfig {
    [pscustomobject]@{
        enabled = $true
        targetHotkey = [pscustomobject]@{
            modifier = "LShift"
            key = "Z"
        }
        timing = [pscustomobject]@{
            holdMs = 140
            cooldownMs = 500
            preSendDelayMs = 120
        }
        audioKeepAlive = [pscustomobject]@{
            enabled = $true
            waveFrequencyHz = 220
            waveSeconds = 5
        }
        statusSound = [pscustomobject]@{
            enabled = $true
        }
        logging = [pscustomobject]@{
            enabled = $true
            directory = "logs"
        }
        tray = [pscustomobject]@{
            enabled = $true
            showBalloonOnStart = $true
        }
    }
}

function Get-PropertyOrDefault($Object, [string]$Name, $Default) {
    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) {
        return $Object.$Name
    }
    return $Default
}

function Get-VirtualKey([string]$Name) {
    $map = @{
        "Shift" = 0x10; "LShift" = 0xA0; "RShift" = 0xA1
        "Ctrl" = 0x11; "LCtrl" = 0xA2; "RCtrl" = 0xA3
        "Alt" = 0x12; "LAlt" = 0xA4; "RAlt" = 0xA5
        "Z" = 0x5A
    }

    if ($map.ContainsKey($Name)) {
        return [int]$map[$Name]
    }

    if ($Name -match '^[A-Za-z]$') {
        return [int][char]($Name.ToUpperInvariant())
    }

    throw "Unsupported key in config: $Name"
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    New-DefaultConfig | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
}

$config = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
$default = New-DefaultConfig

$target = Get-PropertyOrDefault $config "targetHotkey" $default.targetHotkey
$timing = Get-PropertyOrDefault $config "timing" $default.timing
$audio = Get-PropertyOrDefault $config "audioKeepAlive" $default.audioKeepAlive
$sound = Get-PropertyOrDefault $config "statusSound" $default.statusSound
$logging = Get-PropertyOrDefault $config "logging" $default.logging
$tray = Get-PropertyOrDefault $config "tray" $default.tray

$isEnabled = [bool](Get-PropertyOrDefault $config "enabled" $true)
$modifierVk = Get-VirtualKey ([string](Get-PropertyOrDefault $target "modifier" "LShift"))
$keyVk = Get-VirtualKey ([string](Get-PropertyOrDefault $target "key" "Z"))
$holdMs = [int](Get-PropertyOrDefault $timing "holdMs" 140)
$cooldownMs = [int](Get-PropertyOrDefault $timing "cooldownMs" 500)
$preSendDelayMs = [int](Get-PropertyOrDefault $timing "preSendDelayMs" 120)
$audioEnabled = [bool](Get-PropertyOrDefault $audio "enabled" $true) -and (-not $NoAudioKeepAlive)
$waveFrequencyHz = [int](Get-PropertyOrDefault $audio "waveFrequencyHz" 220)
$waveSeconds = [int](Get-PropertyOrDefault $audio "waveSeconds" 5)
$soundEnabled = [bool](Get-PropertyOrDefault $sound "enabled" $true)
$loggingEnabled = [bool](Get-PropertyOrDefault $logging "enabled" $true)
$logDirectoryConfig = [string](Get-PropertyOrDefault $logging "directory" "logs")
$showBalloonOnStart = [bool](Get-PropertyOrDefault $tray "showBalloonOnStart" $true)

if ([System.IO.Path]::IsPathRooted($logDirectoryConfig)) {
    $logDirectory = $logDirectoryConfig
} else {
    $logDirectory = Join-Path $PSScriptRoot $logDirectoryConfig
}

if (-not (Test-Path -LiteralPath $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory | Out-Null
}

$logPath = Join-Path $logDirectory ("headset-button-" + (Get-Date -Format "yyyyMMdd") + ".log")

Add-Type -TypeDefinition @"
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Media;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

public class HeadsetButtonApp : Form
{
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_SYSKEYUP = 0x0105;
    private const int VK_MEDIA_PLAY_PAUSE = 0xB3;
    private const int INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;

    private static readonly ushort[] keysToRelease = new ushort[] { 0x5A, 0xA0, 0xA1, 0x10, 0x11, 0x12 };
    private static LowLevelKeyboardProc proc = HookCallback;
    private static IntPtr hookId = IntPtr.Zero;
    private static long lastPressTicks = 0;
    private static bool enabled = true;
    private static bool soundEnabled = true;
    private static bool loggingEnabled = true;
    private static int holdMs = 140;
    private static int cooldownMs = 500;
    private static int preSendDelayMs = 120;
    private static ushort modifierVk = 0xA0;
    private static ushort keyVk = 0x5A;
    private static string configPath = "";
    private static string logPath = "";
    private static string logDirectory = "";

    private NotifyIcon trayIcon;
    private ToolStripMenuItem enabledMenuItem;

    public HeadsetButtonApp()
    {
        ShowInTaskbar = false;
        WindowState = FormWindowState.Minimized;
        FormBorderStyle = FormBorderStyle.FixedToolWindow;
        Opacity = 0;
    }

    protected override void SetVisibleCore(bool value)
    {
        base.SetVisibleCore(false);
    }

    public static void Configure(
        bool initialEnabled,
        int targetModifierVk,
        int targetKeyVk,
        int holdMilliseconds,
        int cooldownMilliseconds,
        int preSendDelayMilliseconds,
        bool enableSound,
        bool enableLogging,
        string configuredConfigPath,
        string configuredLogPath,
        string configuredLogDirectory)
    {
        enabled = initialEnabled;
        modifierVk = (ushort)targetModifierVk;
        keyVk = (ushort)targetKeyVk;
        holdMs = Math.Max(40, holdMilliseconds);
        cooldownMs = Math.Max(150, cooldownMilliseconds);
        preSendDelayMs = Math.Max(0, preSendDelayMilliseconds);
        soundEnabled = enableSound;
        loggingEnabled = enableLogging;
        configPath = configuredConfigPath;
        logPath = configuredLogPath;
        logDirectory = configuredLogDirectory;
    }

    public static void RunApp(bool showBalloonOnStart)
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        HeadsetButtonApp app = new HeadsetButtonApp();
        hookId = SetHook(proc);
        Log("low level hook installed=" + (hookId != IntPtr.Zero) + " err=" + Marshal.GetLastWin32Error());

        WarmUp();
        app.SetupTray(showBalloonOnStart);
        Application.Run(app);

        app.DisposeTray();
        UnhookWindowsHookEx(hookId);
        Log("exited");
    }

    public static void TestHotkey()
    {
        Log("manual hotkey test");
        SendTargetHotkey();
    }

    private void SetupTray(bool showBalloonOnStart)
    {
        enabledMenuItem = new ToolStripMenuItem("Enabled", null, delegate {
            enabled = !enabled;
            UpdateTrayState();
            Log("enabled=" + enabled);
            PlayStatusSound(enabled);
        });
        enabledMenuItem.Checked = enabled;

        ContextMenuStrip menu = new ContextMenuStrip();
        menu.Items.Add(enabledMenuItem);
        menu.Items.Add(new ToolStripMenuItem("Test hotkey", null, delegate { ThreadPool.QueueUserWorkItem(_ => TestHotkey()); }));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Open config", null, delegate { OpenPath(configPath); }));
        menu.Items.Add(new ToolStripMenuItem("Open log folder", null, delegate { OpenPath(logDirectory); }));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Exit", null, delegate { Application.Exit(); }));

        trayIcon = new NotifyIcon();
        trayIcon.Icon = SystemIcons.Application;
        trayIcon.Text = "Headset button -> hotkey";
        trayIcon.ContextMenuStrip = menu;
        trayIcon.Visible = true;
        trayIcon.DoubleClick += delegate { ThreadPool.QueueUserWorkItem(_ => TestHotkey()); };
        UpdateTrayState();

        if (showBalloonOnStart)
        {
            trayIcon.ShowBalloonTip(2500, "Headset hotkey is running", "Right-click the tray icon for options.", ToolTipIcon.Info);
        }
    }

    private void DisposeTray()
    {
        if (trayIcon != null)
        {
            trayIcon.Visible = false;
            trayIcon.Dispose();
        }
    }

    private void UpdateTrayState()
    {
        if (enabledMenuItem != null)
        {
            enabledMenuItem.Checked = enabled;
        }
        if (trayIcon != null)
        {
            trayIcon.Text = enabled ? "Headset button -> hotkey: enabled" : "Headset button -> hotkey: paused";
        }
    }

    private static void OpenPath(string path)
    {
        try
        {
            ProcessStartInfo info = new ProcessStartInfo();
            info.FileName = path;
            info.UseShellExecute = true;
            Process.Start(info);
        }
        catch (Exception ex)
        {
            Log("open path failed: " + ex.Message);
        }
    }

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            int vkCode = Marshal.ReadInt32(lParam);
            if (vkCode == VK_MEDIA_PLAY_PAUSE)
            {
                if (wParam == (IntPtr)WM_KEYDOWN || wParam == (IntPtr)WM_SYSKEYDOWN)
                {
                    long now = Stopwatch.GetTimestamp();
                    long previous = Interlocked.Read(ref lastPressTicks);
                    double elapsedMs = previous == 0 ? 1000 : (now - previous) * 1000.0 / Stopwatch.Frequency;

                    if (enabled && elapsedMs > cooldownMs)
                    {
                        Interlocked.Exchange(ref lastPressTicks, now);
                        Log("media key captured");
                        ThreadPool.QueueUserWorkItem(_ =>
                        {
                            Thread.Sleep(80);
                            SendTargetHotkey();
                        });
                    }
                    else if (!enabled)
                    {
                        Log("media key ignored because app is paused");
                    }
                }

                if (wParam == (IntPtr)WM_KEYUP || wParam == (IntPtr)WM_SYSKEYUP)
                {
                    return (IntPtr)1;
                }

                return (IntPtr)1;
            }
        }

        return CallNextHookEx(hookId, nCode, wParam, lParam);
    }

    private static void WarmUp()
    {
        Log("warming up keyboard injection");
        ReleaseHotkeyKeys();
    }

    private static void SendTargetHotkey()
    {
        Log("sending target hotkey");
        ReleaseHotkeyKeys();
        Thread.Sleep(preSendDelayMs);

        SendKey(modifierVk, false);
        Thread.Sleep(holdMs);
        SendKey(keyVk, false);
        Thread.Sleep(holdMs);
        SendKey(keyVk, true);
        Thread.Sleep(60);
        SendKey(modifierVk, true);

        Log("target hotkey sent");
        PlayStatusSound(true);
    }

    private static void ReleaseHotkeyKeys()
    {
        SendKey(keyVk, true);
        Thread.Sleep(20);
        SendKey(modifierVk, true);
        foreach (ushort key in keysToRelease)
        {
            Thread.Sleep(20);
            SendKey(key, true);
        }
    }

    private static void SendKey(ushort virtualKey, bool keyUp)
    {
        INPUT[] inputs = new INPUT[]
        {
            new INPUT
            {
                type = INPUT_KEYBOARD,
                u = new InputUnion
                {
                    ki = new KEYBDINPUT
                    {
                        wVk = virtualKey,
                        wScan = 0,
                        dwFlags = keyUp ? KEYEVENTF_KEYUP : 0u,
                        time = 0,
                        dwExtraInfo = UIntPtr.Zero
                    }
                }
            }
        };

        uint sent = SendInput(1, inputs, Marshal.SizeOf(typeof(INPUT)));
        if (sent != 1)
        {
            int error = Marshal.GetLastWin32Error();
            Log("SendInput failed vk=0x" + virtualKey.ToString("X") + " up=" + keyUp + " err=" + error + ", using keybd_event");
            keybd_event((byte)virtualKey, 0, keyUp ? KEYEVENTF_KEYUP : 0u, UIntPtr.Zero);
        }
    }

    private static void PlayStatusSound(bool success)
    {
        if (!soundEnabled) return;
        try
        {
            if (success) SystemSounds.Asterisk.Play();
            else SystemSounds.Exclamation.Play();
        }
        catch {}
    }

    private static void Log(string message)
    {
        string line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + " " + message;
        Console.WriteLine(line);
        if (!loggingEnabled || String.IsNullOrEmpty(logPath)) return;

        try
        {
            File.AppendAllText(logPath, line + Environment.NewLine);
        }
        catch {}
    }

    private static IntPtr SetHook(LowLevelKeyboardProc proc)
    {
        using (Process curProcess = Process.GetCurrentProcess())
        using (ProcessModule curModule = curProcess.MainModule)
        {
            return SetWindowsHookEx(WH_KEYBOARD_LL, proc, GetModuleHandle(curModule.ModuleName), 0);
        }
    }

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public int type;
        public InputUnion u;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)]
        public MOUSEINPUT mi;
        [FieldOffset(0)]
        public KEYBDINPUT ki;
        [FieldOffset(0)]
        public HARDWAREINPUT hi;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HARDWAREINPUT
    {
        public uint uMsg;
        public ushort wParamL;
        public ushort wParamH;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}

public static class AudioKeepAlive
{
    private static SoundPlayer player;

    public static void Start(string wavePath, int frequencyHz, int seconds)
    {
        CreateQuietWave(wavePath, Math.Max(20, frequencyHz), Math.Max(1, seconds));
        player = new SoundPlayer(wavePath);
        player.Load();
        player.PlayLooping();
        Console.WriteLine(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + " quiet audio keep-alive started");
    }

    private static void CreateQuietWave(string path, int frequencyHz, int seconds)
    {
        int sampleRate = 44100;
        short channels = 1;
        short bitsPerSample = 16;
        int sampleCount = sampleRate * seconds;
        short blockAlign = (short)(channels * bitsPerSample / 8);
        int byteRate = sampleRate * blockAlign;
        int dataSize = sampleCount * blockAlign;

        using (BinaryWriter writer = new BinaryWriter(File.Open(path, FileMode.Create, FileAccess.Write, FileShare.Read)))
        {
            writer.Write(new char[] { 'R', 'I', 'F', 'F' });
            writer.Write(36 + dataSize);
            writer.Write(new char[] { 'W', 'A', 'V', 'E' });
            writer.Write(new char[] { 'f', 'm', 't', ' ' });
            writer.Write(16);
            writer.Write((short)1);
            writer.Write(channels);
            writer.Write(sampleRate);
            writer.Write(byteRate);
            writer.Write(blockAlign);
            writer.Write(bitsPerSample);
            writer.Write(new char[] { 'd', 'a', 't', 'a' });
            writer.Write(dataSize);

            for (int i = 0; i < sampleCount; i++)
            {
                double phase = 2.0 * Math.PI * frequencyHz * i / sampleRate;
                short sample = (short)Math.Round(Math.Sin(phase));
                writer.Write(sample);
            }
        }
    }
}
"@ -ReferencedAssemblies System.Windows.Forms,System.Drawing

if ($audioEnabled) {
    $keepAliveWave = Join-Path $env:TEMP "headset-button-keepalive.wav"
    [AudioKeepAlive]::Start($keepAliveWave, $waveFrequencyHz, $waveSeconds)
} else {
    Write-Host "Audio keep-alive disabled."
}

[HeadsetButtonApp]::Configure(
    $isEnabled,
    $modifierVk,
    $keyVk,
    $holdMs,
    $cooldownMs,
    $preSendDelayMs,
    $soundEnabled,
    $loggingEnabled,
    (Resolve-Path -LiteralPath $ConfigPath).Path,
    $logPath,
    $logDirectory
)

if ($Test) {
    Write-Host "Sending configured hotkey in 2 seconds. Put your cursor in a text box now."
    Start-Sleep -Seconds 2
    [HeadsetButtonApp]::TestHotkey()
    Write-Host "Done."
    exit
}

Write-Host "Headset button hotkey is running."
Write-Host "Config=$ConfigPath"
Write-Host "Log=$logPath"
Write-Host "AudioKeepAlive=$audioEnabled"
Write-Host "Use the tray icon to pause, test, open config/logs, or exit."
[HeadsetButtonApp]::RunApp($showBalloonOnStart)
