param(
    [int]$HoldMs = 180,
    [int]$CooldownMs = 500
)

Add-Type -TypeDefinition @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

public class HeadsetButtonDiagnoser : Form
{
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_SYSKEYUP = 0x0105;
    private const int WM_HOTKEY = 0x0312;
    private const int VK_MEDIA_PLAY_PAUSE = 0xB3;
    private const int VK_F8 = 0x77;
    private const int HOTKEY_MEDIA_ID = 1001;
    private const int HOTKEY_F8_ID = 1002;
    private const int INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const ushort VK_LSHIFT = 0xA0;
    private const ushort VK_Z = 0x5A;

    private static LowLevelKeyboardProc proc = HookCallback;
    private static IntPtr hookId = IntPtr.Zero;
    private static HeadsetButtonDiagnoser current;
    private static long lastSendTicks = 0;
    private static int holdMs = 180;
    private static int cooldownMs = 500;

    public static void Configure(int holdMilliseconds, int cooldownMilliseconds)
    {
        holdMs = Math.Max(60, holdMilliseconds);
        cooldownMs = Math.Max(150, cooldownMilliseconds);
    }

    public static void RunDiagnoser()
    {
        Application.EnableVisualStyles();
        current = new HeadsetButtonDiagnoser();
        current.Text = "Headset Button Diagnoser";
        current.Width = 360;
        current.Height = 120;
        current.ShowInTaskbar = false;
        current.WindowState = FormWindowState.Minimized;

        bool mediaRegistered = RegisterHotKey(current.Handle, HOTKEY_MEDIA_ID, 0, VK_MEDIA_PLAY_PAUSE);
        bool f8Registered = RegisterHotKey(current.Handle, HOTKEY_F8_ID, 0, VK_F8);
        Console.WriteLine(Time() + " RegisterHotKey media=" + mediaRegistered + " err=" + Marshal.GetLastWin32Error());
        Console.WriteLine(Time() + " RegisterHotKey F8=" + f8Registered + " err=" + Marshal.GetLastWin32Error());

        hookId = SetHook(proc);
        Console.WriteLine(Time() + " low level hook installed=" + (hookId != IntPtr.Zero) + " err=" + Marshal.GetLastWin32Error());
        LogForeground();

        Application.Run(current);

        UnregisterHotKey(current.Handle, HOTKEY_MEDIA_ID);
        UnregisterHotKey(current.Handle, HOTKEY_F8_ID);
        UnhookWindowsHookEx(hookId);
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_HOTKEY)
        {
            int id = m.WParam.ToInt32();
            if (id == HOTKEY_MEDIA_ID)
            {
                Console.WriteLine(Time() + " WM_HOTKEY media");
                TriggerSend("WM_HOTKEY media");
                return;
            }
            if (id == HOTKEY_F8_ID)
            {
                Console.WriteLine(Time() + " WM_HOTKEY F8 manual test");
                TriggerSend("WM_HOTKEY F8");
                return;
            }
        }

        base.WndProc(ref m);
    }

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            KBDLLHOOKSTRUCT data = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));
            if (data.vkCode == VK_MEDIA_PLAY_PAUSE)
            {
                string msg = MessageName(wParam);
                Console.WriteLine(Time() + " LL hook media " + msg + " scan=" + data.scanCode + " flags=0x" + data.flags.ToString("X"));

                if (wParam == (IntPtr)WM_KEYDOWN || wParam == (IntPtr)WM_SYSKEYDOWN)
                {
                    TriggerSend("LL hook media");
                }

                return (IntPtr)1;
            }
        }

        return CallNextHookEx(hookId, nCode, wParam, lParam);
    }

    private static void TriggerSend(string source)
    {
        long now = Stopwatch.GetTimestamp();
        long previous = Interlocked.Read(ref lastSendTicks);
        double elapsedMs = previous == 0 ? 9999 : (now - previous) * 1000.0 / Stopwatch.Frequency;

        if (elapsedMs < cooldownMs)
        {
            Console.WriteLine(Time() + " ignored duplicate from " + source + " (" + ((int)elapsedMs) + "ms)");
            return;
        }

        Interlocked.Exchange(ref lastSendTicks, now);
        LogForeground();
        ThreadPool.QueueUserWorkItem(_ =>
        {
            Thread.Sleep(140);
            SendShiftZ(source);
        });
    }

    private static void SendShiftZ(string source)
    {
        Console.WriteLine(Time() + " sending Left Shift + Z from " + source);
        SendKey(VK_Z, true);
        Thread.Sleep(30);
        SendKey(VK_LSHIFT, true);
        Thread.Sleep(120);
        SendKey(VK_LSHIFT, false);
        Thread.Sleep(holdMs);
        SendKey(VK_Z, false);
        Thread.Sleep(holdMs);
        SendKey(VK_Z, true);
        Thread.Sleep(80);
        SendKey(VK_LSHIFT, true);
        Console.WriteLine(Time() + " send sequence done");
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
            Console.WriteLine(Time() + " SendInput failed vk=0x" + virtualKey.ToString("X") + " up=" + keyUp + " err=" + error + ", using keybd_event");
            keybd_event((byte)virtualKey, 0, keyUp ? KEYEVENTF_KEYUP : 0u, UIntPtr.Zero);
        }
    }

    private static void LogForeground()
    {
        IntPtr hwnd = GetForegroundWindow();
        StringBuilder title = new StringBuilder(260);
        GetWindowText(hwnd, title, title.Capacity);
        uint pid;
        GetWindowThreadProcessId(hwnd, out pid);
        string procName = "";
        try
        {
            procName = Process.GetProcessById((int)pid).ProcessName;
        }
        catch {}
        Console.WriteLine(Time() + " foreground pid=" + pid + " proc=" + procName + " title=\"" + title.ToString() + "\"");
    }

    private static string Time()
    {
        return DateTime.Now.ToString("HH:mm:ss.fff");
    }

    private static string MessageName(IntPtr wParam)
    {
        if (wParam == (IntPtr)WM_KEYDOWN) return "KEYDOWN";
        if (wParam == (IntPtr)WM_KEYUP) return "KEYUP";
        if (wParam == (IntPtr)WM_SYSKEYDOWN) return "SYSKEYDOWN";
        if (wParam == (IntPtr)WM_SYSKEYUP) return "SYSKEYUP";
        return "msg=" + wParam;
    }

    private static IntPtr SetHook(LowLevelKeyboardProc proc)
    {
        using (Process curProcess = Process.GetCurrentProcess())
        using (ProcessModule curModule = curProcess.MainModule)
        {
            return SetWindowsHookEx(WH_KEYBOARD_LL, proc, GetModuleHandle(curModule.ModuleName), 0);
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT
    {
        public int vkCode;
        public int scanCode;
        public int flags;
        public int time;
        public IntPtr dwExtraInfo;
    }

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
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, int vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

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

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
}
"@ -ReferencedAssemblies System.Windows.Forms

[HeadsetButtonDiagnoser]::Configure($HoldMs, $CooldownMs)
Write-Host "Headset button diagnoser is running."
Write-Host "Close all previous hotkey/debug windows first."
Write-Host "Tests:"
Write-Host "1. Press headset button before playing any media."
Write-Host "2. Press F8. This manually sends Left Shift + Z without using the headset button."
Write-Host "3. Play/pause any video once, then press headset button again."
Write-Host "Please report the lines printed around each test."
[HeadsetButtonDiagnoser]::RunDiagnoser()
