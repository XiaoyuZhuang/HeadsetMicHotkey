param(
    [int]$HoldMs = 180,
    [int]$CooldownMs = 700
)

Add-Type -TypeDefinition @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

public static class HeadsetButtonDebug
{
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_SYSKEYUP = 0x0105;
    private const int VK_MEDIA_PLAY_PAUSE = 0xB3;
    private const int INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint KEYEVENTF_SCANCODE = 0x0008;
    private const ushort VK_LSHIFT = 0xA0;
    private const ushort VK_RSHIFT = 0xA1;
    private const ushort VK_SHIFT = 0x10;
    private const ushort VK_Z = 0x5A;
    private const ushort SC_LSHIFT = 0x2A;
    private const ushort SC_RSHIFT = 0x36;
    private const ushort SC_Z = 0x2C;

    private static LowLevelKeyboardProc proc = HookCallback;
    private static IntPtr hookId = IntPtr.Zero;
    private static long lastPressTicks = 0;
    private static int holdMs = 180;
    private static int cooldownMs = 700;
    private static int attempt = 0;

    public static void Configure(int holdMilliseconds, int cooldownMilliseconds)
    {
        holdMs = Math.Max(60, holdMilliseconds);
        cooldownMs = Math.Max(250, cooldownMilliseconds);
    }

    public static void Run()
    {
        hookId = SetHook(proc);
        Application.Run();
        UnhookWindowsHookEx(hookId);
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

                    if (elapsedMs > cooldownMs)
                    {
                        Interlocked.Exchange(ref lastPressTicks, now);
                        int current = Interlocked.Increment(ref attempt);
                        Console.WriteLine(DateTime.Now.ToString("HH:mm:ss.fff") + " media key captured -> attempt " + current);
                        ThreadPool.QueueUserWorkItem(_ =>
                        {
                            Thread.Sleep(120);
                            TryAttempt(current);
                        });
                    }
                    else
                    {
                        Console.WriteLine(DateTime.Now.ToString("HH:mm:ss.fff") + " ignored duplicate event (" + ((int)elapsedMs) + "ms)");
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

    private static void TryAttempt(int current)
    {
        int mode = ((current - 1) % 6) + 1;
        Console.WriteLine(DateTime.Now.ToString("HH:mm:ss.fff") + " sending mode " + mode + ": " + ModeName(mode));

        switch (mode)
        {
            case 1:
                SendVk(VK_LSHIFT, false); Sleep(); SendVk(VK_Z, false); Sleep(); SendVk(VK_Z, true); SleepShort(); SendVk(VK_LSHIFT, true);
                break;
            case 2:
                SendScan(SC_LSHIFT, false); Sleep(); SendScan(SC_Z, false); Sleep(); SendScan(SC_Z, true); SleepShort(); SendScan(SC_LSHIFT, true);
                break;
            case 3:
                SendVk(VK_SHIFT, false); Sleep(); SendVk(VK_Z, false); Sleep(); SendVk(VK_Z, true); SleepShort(); SendVk(VK_SHIFT, true);
                break;
            case 4:
                keybd_event((byte)VK_LSHIFT, 0, 0, UIntPtr.Zero); Sleep(); keybd_event((byte)VK_Z, 0, 0, UIntPtr.Zero); Sleep(); keybd_event((byte)VK_Z, 0, KEYEVENTF_KEYUP, UIntPtr.Zero); SleepShort(); keybd_event((byte)VK_LSHIFT, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
                break;
            case 5:
                SendVk(VK_RSHIFT, false); Sleep(); SendVk(VK_Z, false); Sleep(); SendVk(VK_Z, true); SleepShort(); SendVk(VK_RSHIFT, true);
                break;
            case 6:
                SendScan(SC_RSHIFT, false); Sleep(); SendScan(SC_Z, false); Sleep(); SendScan(SC_Z, true); SleepShort(); SendScan(SC_RSHIFT, true);
                break;
        }

        Console.WriteLine(DateTime.Now.ToString("HH:mm:ss.fff") + " attempt " + current + " done");
    }

    private static string ModeName(int mode)
    {
        switch (mode)
        {
            case 1: return "SendInput VK_LSHIFT + Z";
            case 2: return "SendInput scan LSHIFT + Z";
            case 3: return "SendInput generic SHIFT + Z";
            case 4: return "keybd_event VK_LSHIFT + Z";
            case 5: return "SendInput VK_RSHIFT + Z";
            case 6: return "SendInput scan RSHIFT + Z";
            default: return "unknown";
        }
    }

    private static void Sleep()
    {
        Thread.Sleep(holdMs);
    }

    private static void SleepShort()
    {
        Thread.Sleep(80);
    }

    private static bool SendVk(ushort virtualKey, bool keyUp)
    {
        return SendInputKey(virtualKey, 0, keyUp ? KEYEVENTF_KEYUP : 0u);
    }

    private static bool SendScan(ushort scanCode, bool keyUp)
    {
        return SendInputKey(0, scanCode, KEYEVENTF_SCANCODE | (keyUp ? KEYEVENTF_KEYUP : 0u));
    }

    private static bool SendInputKey(ushort virtualKey, ushort scanCode, uint flags)
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
                        wScan = scanCode,
                        dwFlags = flags,
                        time = 0,
                        dwExtraInfo = UIntPtr.Zero
                    }
                }
            }
        };

        uint sent = SendInput(1, inputs, Marshal.SizeOf(typeof(INPUT)));
        if (sent != 1)
        {
            Console.WriteLine("SendInput failed. Last Win32 error: " + Marshal.GetLastWin32Error());
            return false;
        }
        return true;
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
"@ -ReferencedAssemblies System.Windows.Forms

[HeadsetButtonDebug]::Configure($HoldMs, $CooldownMs)
Write-Host "Debug headset listener is running."
Write-Host "Press the headset button once, wait about 1 second, then press again."
Write-Host "Tell Codex which attempt number activates dictation."
Write-Host "HoldMs=$HoldMs CooldownMs=$CooldownMs"
[HeadsetButtonDebug]::Run()
