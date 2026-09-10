using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Media;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: System.Reflection.AssemblyTitle("Headset Mic Hotkey")]
[assembly: System.Reflection.AssemblyDescription("Map a headset media button to a customizable Windows hotkey")]
[assembly: System.Reflection.AssemblyCompany("XiaoyuZhuang")]
[assembly: System.Reflection.AssemblyProduct("Headset Mic Hotkey")]
[assembly: System.Reflection.AssemblyVersion("2.0.0.0")]
[assembly: System.Reflection.AssemblyFileVersion("2.0.0.0")]

namespace HeadsetMicHotkey
{
    internal static class Program
    {
        private const string MutexName = "XiaoyuZhuang.HeadsetMicHotkey.V2.SingleInstance";

        [STAThread]
        private static void Main(string[] args)
        {
            bool createdNew;
            using (Mutex mutex = new Mutex(true, MutexName, out createdNew))
            {
                if (!createdNew)
                {
                    NativeMethods.ShowExistingWindow();
                    return;
                }

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);

                AppSettings settings = SettingsStore.Load();
                bool startupLaunch = Array.Exists(args, delegate(string s) { return string.Equals(s, "--startup", StringComparison.OrdinalIgnoreCase); });
                Application.Run(new HotkeyApplicationContext(settings, startupLaunch));
            }
        }
    }

    internal sealed class HotkeyApplicationContext : ApplicationContext
    {
        private readonly AppSettings settings;
        private readonly MainForm mainForm;
        private readonly NotifyIcon trayIcon;
        private readonly KeyboardMapper mapper;
        private AudioKeepAlive audioKeepAlive;
        private bool exiting;

        public HotkeyApplicationContext(AppSettings settings, bool startupLaunch)
        {
            this.settings = settings;
            this.mapper = new KeyboardMapper(settings);
            this.mapper.Triggered += Mapper_Triggered;

            this.mainForm = new MainForm(settings, mapper);
            this.mainForm.RequestExit += delegate { ExitApplication(); };
            this.mainForm.SettingsChanged += SettingsChanged;

            ContextMenuStrip menu = new ContextMenuStrip();
            ToolStripMenuItem open = new ToolStripMenuItem("Open Headset Mic Hotkey");
            open.Click += delegate { ShowMainWindow(); };
            ToolStripMenuItem toggle = new ToolStripMenuItem(settings.Enabled ? "Pause mapping" : "Enable mapping");
            toggle.Click += delegate
            {
                settings.Enabled = !settings.Enabled;
                mapper.Enabled = settings.Enabled;
                SettingsStore.Save(settings);
                mainForm.RefreshState();
                toggle.Text = settings.Enabled ? "Pause mapping" : "Enable mapping";
            };
            ToolStripMenuItem test = new ToolStripMenuItem("Test hotkey");
            test.Click += delegate { mapper.Test(); };
            ToolStripMenuItem logs = new ToolStripMenuItem("Open log folder");
            logs.Click += delegate { Logger.OpenFolder(); };
            ToolStripMenuItem exit = new ToolStripMenuItem("Exit");
            exit.Click += delegate { ExitApplication(); };
            menu.Items.Add(open);
            menu.Items.Add(toggle);
            menu.Items.Add(test);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(logs);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(exit);

            trayIcon = new NotifyIcon();
            trayIcon.Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            trayIcon.Text = BuildTrayText();
            trayIcon.ContextMenuStrip = menu;
            trayIcon.Visible = true;
            trayIcon.DoubleClick += delegate { ShowMainWindow(); };

            mapper.Start();
            ApplyAudioKeepAlive();

            if (!startupLaunch || !settings.StartMinimized)
                ShowMainWindow();
        }

        private string BuildTrayText()
        {
            string state = settings.Enabled ? "Enabled" : "Paused";
            string text = "Headset Mic Hotkey - " + state + " - " + HotkeyNames.ToDisplayString(settings.TargetHotkey);
            return text.Length > 63 ? text.Substring(0, 63) : text;
        }

        private void Mapper_Triggered(object sender, EventArgs e)
        {
            if (mainForm.IsHandleCreated)
            {
                mainForm.BeginInvoke((MethodInvoker)delegate
                {
                    mainForm.SetLastTrigger(DateTime.Now);
                });
            }
        }

        private void SettingsChanged(object sender, EventArgs e)
        {
            mapper.Reload(settings);
            ApplyAudioKeepAlive();
            trayIcon.Text = BuildTrayText();
            SettingsStore.Save(settings);
        }

        private void ApplyAudioKeepAlive()
        {
            if (audioKeepAlive != null)
            {
                audioKeepAlive.Dispose();
                audioKeepAlive = null;
            }

            if (settings.AudioKeepAlive)
            {
                audioKeepAlive = new AudioKeepAlive();
                audioKeepAlive.Start(settings.KeepAliveFrequencyHz, settings.KeepAliveSeconds);
            }
        }

        private void ShowMainWindow()
        {
            if (!mainForm.Visible)
                mainForm.Show();
            if (mainForm.WindowState == FormWindowState.Minimized)
                mainForm.WindowState = FormWindowState.Normal;
            mainForm.Activate();
            mainForm.BringToFront();
        }

        private void ExitApplication()
        {
            if (exiting) return;
            exiting = true;
            trayIcon.Visible = false;
            trayIcon.Dispose();
            mapper.Dispose();
            if (audioKeepAlive != null) audioKeepAlive.Dispose();
            mainForm.AllowClose = true;
            mainForm.Close();
            ExitThread();
        }
    }

    internal sealed class MainForm : Form
    {
        private readonly AppSettings settings;
        private readonly KeyboardMapper mapper;
        private Label statusLabel;
        private Label hotkeyLabel;
        private Label lastTriggerLabel;
        private Button enabledButton;
        private Button audioButton;
        private Button startupButton;
        public bool AllowClose { get; set; }

        public event EventHandler RequestExit;
        public event EventHandler SettingsChanged;

        public MainForm(AppSettings settings, KeyboardMapper mapper)
        {
            this.settings = settings;
            this.mapper = mapper;

            Text = "Headset Mic Hotkey";
            Width = 560;
            Height = 610;
            MinimumSize = new Size(520, 570);
            StartPosition = FormStartPosition.CenterScreen;
            Font = new Font("Segoe UI", 10F);
            KeyPreview = true;
            FormClosing += MainForm_FormClosing;

            BuildUi();
            RefreshState();
            ThemeHelper.Apply(this);
        }

        private void BuildUi()
        {
            TableLayoutPanel root = new TableLayoutPanel();
            root.Dock = DockStyle.Fill;
            root.Padding = new Padding(28, 22, 28, 24);
            root.RowCount = 8;
            root.ColumnCount = 1;
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 58));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 46));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 180));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 62));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 62));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 62));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
            Controls.Add(root);

            Label title = new Label();
            title.Text = "Headset Mic Hotkey";
            title.Font = new Font("Segoe UI Semibold", 20F);
            title.Dock = DockStyle.Fill;
            title.TextAlign = ContentAlignment.MiddleLeft;
            root.Controls.Add(title, 0, 0);

            statusLabel = new Label();
            statusLabel.Dock = DockStyle.Fill;
            statusLabel.Font = new Font("Segoe UI Semibold", 10F);
            statusLabel.TextAlign = ContentAlignment.MiddleLeft;
            root.Controls.Add(statusLabel, 0, 1);

            Panel card = new Panel();
            card.Dock = DockStyle.Fill;
            card.Padding = new Padding(18);
            card.Margin = new Padding(0, 4, 0, 12);
            card.BorderStyle = BorderStyle.FixedSingle;
            root.Controls.Add(card, 0, 2);

            TableLayoutPanel cardLayout = new TableLayoutPanel();
            cardLayout.Dock = DockStyle.Fill;
            cardLayout.ColumnCount = 1;
            cardLayout.RowCount = 4;
            cardLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 30));
            cardLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 36));
            cardLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
            cardLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            card.Controls.Add(cardLayout);

            Label source = new Label();
            source.Text = "Headset Play / Pause";
            source.Dock = DockStyle.Fill;
            source.TextAlign = ContentAlignment.MiddleCenter;
            cardLayout.Controls.Add(source, 0, 0);

            Label arrow = new Label();
            arrow.Text = "↓";
            arrow.Dock = DockStyle.Fill;
            arrow.Font = new Font("Segoe UI", 15F);
            arrow.TextAlign = ContentAlignment.MiddleCenter;
            cardLayout.Controls.Add(arrow, 0, 1);

            hotkeyLabel = new Label();
            hotkeyLabel.Dock = DockStyle.Fill;
            hotkeyLabel.Font = new Font("Segoe UI Semibold", 18F);
            hotkeyLabel.TextAlign = ContentAlignment.MiddleCenter;
            cardLayout.Controls.Add(hotkeyLabel, 0, 2);

            FlowLayoutPanel cardButtons = new FlowLayoutPanel();
            cardButtons.FlowDirection = FlowDirection.LeftToRight;
            cardButtons.WrapContents = false;
            cardButtons.AutoSize = true;
            cardButtons.Anchor = AnchorStyles.None;
            Button record = MakeButton("Record new hotkey", 160);
            record.Click += Record_Click;
            Button test = MakeButton("Test", 90);
            test.Click += delegate { mapper.Test(); };
            cardButtons.Controls.Add(record);
            cardButtons.Controls.Add(test);
            cardLayout.Controls.Add(cardButtons, 0, 3);

            enabledButton = MakeWideSettingButton("Mapping", "");
            enabledButton.Click += delegate
            {
                settings.Enabled = !settings.Enabled;
                mapper.Enabled = settings.Enabled;
                RaiseSettingsChanged();
                RefreshState();
            };
            root.Controls.Add(enabledButton, 0, 3);

            audioButton = MakeWideSettingButton("Audio keep-alive", "Keeps some headset buttons responsive");
            audioButton.Click += delegate
            {
                settings.AudioKeepAlive = !settings.AudioKeepAlive;
                RaiseSettingsChanged();
                RefreshState();
            };
            root.Controls.Add(audioButton, 0, 4);

            startupButton = MakeWideSettingButton("Run at startup", "Starts silently in the tray");
            startupButton.Click += delegate
            {
                settings.RunAtStartup = !settings.RunAtStartup;
                StartupService.SetEnabled(settings.RunAtStartup);
                RaiseSettingsChanged();
                RefreshState();
            };
            root.Controls.Add(startupButton, 0, 5);

            lastTriggerLabel = new Label();
            lastTriggerLabel.Dock = DockStyle.Top;
            lastTriggerLabel.Height = 40;
            lastTriggerLabel.TextAlign = ContentAlignment.MiddleLeft;
            lastTriggerLabel.Text = "Waiting for headset button...";
            root.Controls.Add(lastTriggerLabel, 0, 6);

            FlowLayoutPanel bottom = new FlowLayoutPanel();
            bottom.Dock = DockStyle.Fill;
            bottom.FlowDirection = FlowDirection.RightToLeft;
            Button advanced = MakeButton("Advanced", 105);
            advanced.Click += Advanced_Click;
            Button exit = MakeButton("Exit", 80);
            exit.Click += delegate { if (RequestExit != null) RequestExit(this, EventArgs.Empty); };
            bottom.Controls.Add(exit);
            bottom.Controls.Add(advanced);
            root.Controls.Add(bottom, 0, 7);
        }

        private Button MakeButton(string text, int width)
        {
            Button b = new Button();
            b.Text = text;
            b.Width = width;
            b.Height = 34;
            b.FlatStyle = FlatStyle.Flat;
            b.FlatAppearance.BorderSize = 1;
            b.Margin = new Padding(5);
            b.Cursor = Cursors.Hand;
            return b;
        }

        private Button MakeWideSettingButton(string title, string subtitle)
        {
            Button b = new Button();
            b.Dock = DockStyle.Fill;
            b.Margin = new Padding(0, 5, 0, 5);
            b.FlatStyle = FlatStyle.Flat;
            b.TextAlign = ContentAlignment.MiddleLeft;
            b.Padding = new Padding(12, 0, 12, 0);
            b.Tag = new string[] { title, subtitle };
            return b;
        }

        private void Record_Click(object sender, EventArgs e)
        {
            bool wasEnabled = mapper.Enabled;
            mapper.Enabled = false;
            using (HotkeyRecorderDialog dialog = new HotkeyRecorderDialog())
            {
                if (dialog.ShowDialog(this) == DialogResult.OK && dialog.CapturedHotkey != null)
                {
                    settings.TargetHotkey = dialog.CapturedHotkey;
                    RaiseSettingsChanged();
                }
            }
            mapper.Enabled = wasEnabled;
            RefreshState();
        }

        private void Advanced_Click(object sender, EventArgs e)
        {
            using (AdvancedForm form = new AdvancedForm(settings))
            {
                if (form.ShowDialog(this) == DialogResult.OK)
                {
                    RaiseSettingsChanged();
                    RefreshState();
                }
            }
        }

        private void RaiseSettingsChanged()
        {
            if (SettingsChanged != null) SettingsChanged(this, EventArgs.Empty);
        }

        public void RefreshState()
        {
            hotkeyLabel.Text = HotkeyNames.ToDisplayString(settings.TargetHotkey);
            statusLabel.Text = settings.Enabled ? "●  Running" : "○  Paused";
            statusLabel.ForeColor = settings.Enabled ? Color.FromArgb(22, 163, 74) : Color.FromArgb(107, 114, 128);
            UpdateSettingButton(enabledButton, "Mapping", "Convert headset button to the selected hotkey", settings.Enabled);
            UpdateSettingButton(audioButton, "Audio keep-alive", "Keeps some headset buttons responsive", settings.AudioKeepAlive);
            UpdateSettingButton(startupButton, "Run at startup", "Starts silently in the tray", settings.RunAtStartup);
        }

        private void UpdateSettingButton(Button button, string title, string subtitle, bool enabled)
        {
            button.Text = title + "     " + (enabled ? "ON" : "OFF") + (string.IsNullOrEmpty(subtitle) ? "" : Environment.NewLine + subtitle);
        }

        public void SetLastTrigger(DateTime time)
        {
            lastTriggerLabel.Text = "Last trigger: " + time.ToString("HH:mm:ss") + "    " + HotkeyNames.ToDisplayString(settings.TargetHotkey);
        }

        private void MainForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            if (!AllowClose && e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;
                Hide();
            }
        }
    }

    internal sealed class AdvancedForm : Form
    {
        private readonly AppSettings settings;
        private NumericUpDown preDelay;
        private NumericUpDown hold;
        private NumericUpDown cooldown;
        private NumericUpDown frequency;
        private NumericUpDown seconds;
        private CheckBox sound;
        private CheckBox startMinimized;

        public AdvancedForm(AppSettings settings)
        {
            this.settings = settings;
            Text = "Advanced settings";
            Width = 440;
            Height = 470;
            StartPosition = FormStartPosition.CenterParent;
            Font = new Font("Segoe UI", 10F);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;

            TableLayoutPanel layout = new TableLayoutPanel();
            layout.Dock = DockStyle.Fill;
            layout.Padding = new Padding(24);
            layout.ColumnCount = 2;
            layout.RowCount = 8;
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 62));
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 38));
            Controls.Add(layout);

            preDelay = AddNumber(layout, 0, "Pre-send delay (ms)", settings.PreSendDelayMs, 0, 2000);
            hold = AddNumber(layout, 1, "Key hold time (ms)", settings.HoldMs, 20, 2000);
            cooldown = AddNumber(layout, 2, "Trigger cooldown (ms)", settings.CooldownMs, 100, 5000);
            frequency = AddNumber(layout, 3, "Keep-alive frequency (Hz)", settings.KeepAliveFrequencyHz, 20, 2000);
            seconds = AddNumber(layout, 4, "Keep-alive loop length (s)", settings.KeepAliveSeconds, 1, 30);

            sound = new CheckBox();
            sound.Text = "Play a sound after triggering";
            sound.Checked = settings.StatusSound;
            sound.AutoSize = true;
            layout.Controls.Add(sound, 0, 5);
            layout.SetColumnSpan(sound, 2);

            startMinimized = new CheckBox();
            startMinimized.Text = "Start in tray when launched at Windows startup";
            startMinimized.Checked = settings.StartMinimized;
            startMinimized.AutoSize = true;
            layout.Controls.Add(startMinimized, 0, 6);
            layout.SetColumnSpan(startMinimized, 2);

            FlowLayoutPanel buttons = new FlowLayoutPanel();
            buttons.FlowDirection = FlowDirection.RightToLeft;
            buttons.Dock = DockStyle.Fill;
            Button ok = new Button();
            ok.Text = "Save";
            ok.Width = 90;
            ok.DialogResult = DialogResult.OK;
            Button cancel = new Button();
            cancel.Text = "Cancel";
            cancel.Width = 90;
            cancel.DialogResult = DialogResult.Cancel;
            buttons.Controls.Add(ok);
            buttons.Controls.Add(cancel);
            layout.Controls.Add(buttons, 0, 7);
            layout.SetColumnSpan(buttons, 2);

            AcceptButton = ok;
            CancelButton = cancel;
            ok.Click += delegate
            {
                settings.PreSendDelayMs = (int)preDelay.Value;
                settings.HoldMs = (int)hold.Value;
                settings.CooldownMs = (int)cooldown.Value;
                settings.KeepAliveFrequencyHz = (int)frequency.Value;
                settings.KeepAliveSeconds = (int)seconds.Value;
                settings.StatusSound = sound.Checked;
                settings.StartMinimized = startMinimized.Checked;
            };
            ThemeHelper.Apply(this);
        }

        private NumericUpDown AddNumber(TableLayoutPanel layout, int row, string labelText, int value, int min, int max)
        {
            Label label = new Label();
            label.Text = labelText;
            label.Dock = DockStyle.Fill;
            label.TextAlign = ContentAlignment.MiddleLeft;
            NumericUpDown number = new NumericUpDown();
            number.Minimum = min;
            number.Maximum = max;
            number.Value = Math.Max(min, Math.Min(max, value));
            number.Dock = DockStyle.Fill;
            layout.Controls.Add(label, 0, row);
            layout.Controls.Add(number, 1, row);
            return number;
        }
    }

    internal sealed class HotkeyRecorderDialog : Form
    {
        private IntPtr hook;
        private NativeMethods.LowLevelKeyboardProc proc;
        private readonly HashSet<int> modifiers = new HashSet<int>();
        private Label display;
        public HotkeyDefinition CapturedHotkey { get; private set; }

        public HotkeyRecorderDialog()
        {
            Text = "Record hotkey";
            Width = 440;
            Height = 230;
            StartPosition = FormStartPosition.CenterParent;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            Font = new Font("Segoe UI", 10F);

            display = new Label();
            display.Dock = DockStyle.Fill;
            display.Text = "Press the shortcut you want to use\r\n\r\nCtrl, Alt, Shift and Windows key are supported\r\nEsc cancels";
            display.TextAlign = ContentAlignment.MiddleCenter;
            display.Font = new Font("Segoe UI Semibold", 12F);
            Controls.Add(display);

            Shown += delegate { InstallHook(); };
            FormClosed += delegate { RemoveHook(); };
            ThemeHelper.Apply(this);
        }

        private void InstallHook()
        {
            proc = HookCallback;
            hook = NativeMethods.SetKeyboardHook(proc);
        }

        private void RemoveHook()
        {
            if (hook != IntPtr.Zero)
            {
                NativeMethods.UnhookWindowsHookEx(hook);
                hook = IntPtr.Zero;
            }
        }

        private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            if (nCode < 0) return NativeMethods.CallNextHookEx(hook, nCode, wParam, lParam);

            NativeMethods.KBDLLHOOKSTRUCT data = (NativeMethods.KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(NativeMethods.KBDLLHOOKSTRUCT));
            int vk = (int)data.vkCode;
            bool down = wParam == (IntPtr)NativeMethods.WM_KEYDOWN || wParam == (IntPtr)NativeMethods.WM_SYSKEYDOWN;
            bool up = wParam == (IntPtr)NativeMethods.WM_KEYUP || wParam == (IntPtr)NativeMethods.WM_SYSKEYUP;

            if (HotkeyNames.IsModifier(vk))
            {
                if (down) modifiers.Add(HotkeyNames.NormalizeModifier(vk));
                if (up) modifiers.Remove(HotkeyNames.NormalizeModifier(vk));
                BeginInvoke((MethodInvoker)delegate { display.Text = HotkeyNames.ToDisplayString(new HotkeyDefinition(new List<int>(modifiers), 0)) + " ..."; });
                return (IntPtr)1;
            }

            if (down)
            {
                if (vk == (int)Keys.Escape && modifiers.Count == 0)
                {
                    BeginInvoke((MethodInvoker)delegate { DialogResult = DialogResult.Cancel; Close(); });
                    return (IntPtr)1;
                }

                HotkeyDefinition result = new HotkeyDefinition(new List<int>(modifiers), vk);
                BeginInvoke((MethodInvoker)delegate
                {
                    CapturedHotkey = result;
                    display.Text = HotkeyNames.ToDisplayString(result);
                    DialogResult = DialogResult.OK;
                    Close();
                });
                return (IntPtr)1;
            }

            if (up) return (IntPtr)1;
            return (IntPtr)1;
        }
    }

    internal sealed class KeyboardMapper : IDisposable
    {
        private readonly object sync = new object();
        private AppSettings settings;
        private IntPtr hook;
        private NativeMethods.LowLevelKeyboardProc proc;
        private long lastPressTicks;
        public bool Enabled { get; set; }
        public event EventHandler Triggered;

        public KeyboardMapper(AppSettings settings)
        {
            this.settings = settings;
            Enabled = settings.Enabled;
        }

        public void Start()
        {
            proc = HookCallback;
            hook = NativeMethods.SetKeyboardHook(proc);
            Logger.Write("Keyboard hook installed: " + (hook != IntPtr.Zero));
        }

        public void Reload(AppSettings newSettings)
        {
            lock (sync)
            {
                settings = newSettings;
                Enabled = newSettings.Enabled;
            }
        }

        public void Test()
        {
            ThreadPool.QueueUserWorkItem(delegate { SendConfiguredHotkey(); });
        }

        private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            if (nCode >= 0)
            {
                NativeMethods.KBDLLHOOKSTRUCT data = (NativeMethods.KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(NativeMethods.KBDLLHOOKSTRUCT));
                if (data.dwExtraInfo == NativeMethods.InjectedMarker)
                    return NativeMethods.CallNextHookEx(hook, nCode, wParam, lParam);

                if (data.vkCode == NativeMethods.VK_MEDIA_PLAY_PAUSE)
                {
                    bool down = wParam == (IntPtr)NativeMethods.WM_KEYDOWN || wParam == (IntPtr)NativeMethods.WM_SYSKEYDOWN;
                    if (down && Enabled)
                    {
                        long now = Stopwatch.GetTimestamp();
                        long previous = Interlocked.Read(ref lastPressTicks);
                        int cooldown;
                        lock (sync) cooldown = settings.CooldownMs;
                        double elapsed = previous == 0 ? 99999 : (now - previous) * 1000.0 / Stopwatch.Frequency;
                        if (elapsed >= cooldown)
                        {
                            Interlocked.Exchange(ref lastPressTicks, now);
                            ThreadPool.QueueUserWorkItem(delegate
                            {
                                Thread.Sleep(50);
                                SendConfiguredHotkey();
                            });
                        }
                    }
                    return (IntPtr)1;
                }
            }
            return NativeMethods.CallNextHookEx(hook, nCode, wParam, lParam);
        }

        private void SendConfiguredHotkey()
        {
            HotkeyDefinition hotkey;
            int preDelay;
            int hold;
            bool sound;
            lock (sync)
            {
                hotkey = settings.TargetHotkey.Clone();
                preDelay = settings.PreSendDelayMs;
                hold = settings.HoldMs;
                sound = settings.StatusSound;
            }

            if (hotkey.Key == 0) return;
            Logger.Write("Sending " + HotkeyNames.ToDisplayString(hotkey));

            Release(hotkey);
            Thread.Sleep(Math.Max(0, preDelay));
            for (int i = 0; i < hotkey.Modifiers.Count; i++) NativeMethods.SendKey((ushort)hotkey.Modifiers[i], false);
            Thread.Sleep(Math.Max(20, hold));
            NativeMethods.SendKey((ushort)hotkey.Key, false);
            Thread.Sleep(Math.Max(20, hold));
            NativeMethods.SendKey((ushort)hotkey.Key, true);
            for (int i = hotkey.Modifiers.Count - 1; i >= 0; i--) NativeMethods.SendKey((ushort)hotkey.Modifiers[i], true);

            if (sound)
            {
                try { SystemSounds.Asterisk.Play(); } catch { }
            }
            if (Triggered != null) Triggered(this, EventArgs.Empty);
        }

        private void Release(HotkeyDefinition hotkey)
        {
            NativeMethods.SendKey((ushort)hotkey.Key, true);
            for (int i = 0; i < hotkey.Modifiers.Count; i++) NativeMethods.SendKey((ushort)hotkey.Modifiers[i], true);
        }

        public void Dispose()
        {
            if (hook != IntPtr.Zero)
            {
                NativeMethods.UnhookWindowsHookEx(hook);
                hook = IntPtr.Zero;
            }
        }
    }

    internal sealed class AudioKeepAlive : IDisposable
    {
        private SoundPlayer player;
        private string wavePath;

        public void Start(int frequencyHz, int seconds)
        {
            try
            {
                string folder = SettingsStore.AppFolder;
                Directory.CreateDirectory(folder);
                wavePath = Path.Combine(folder, "keepalive.wav");
                CreateQuietWave(wavePath, Math.Max(20, frequencyHz), Math.Max(1, seconds));
                player = new SoundPlayer(wavePath);
                player.Load();
                player.PlayLooping();
                Logger.Write("Audio keep-alive started");
            }
            catch (Exception ex)
            {
                Logger.Write("Audio keep-alive failed: " + ex.Message);
            }
        }

        private static void CreateQuietWave(string path, int frequencyHz, int seconds)
        {
            int sampleRate = 44100;
            short channels = 1;
            short bits = 16;
            int count = sampleRate * seconds;
            short blockAlign = (short)(channels * bits / 8);
            int byteRate = sampleRate * blockAlign;
            int dataSize = count * blockAlign;
            using (BinaryWriter writer = new BinaryWriter(File.Open(path, FileMode.Create, FileAccess.Write, FileShare.Read)))
            {
                writer.Write(Encoding.ASCII.GetBytes("RIFF"));
                writer.Write(36 + dataSize);
                writer.Write(Encoding.ASCII.GetBytes("WAVEfmt "));
                writer.Write(16);
                writer.Write((short)1);
                writer.Write(channels);
                writer.Write(sampleRate);
                writer.Write(byteRate);
                writer.Write(blockAlign);
                writer.Write(bits);
                writer.Write(Encoding.ASCII.GetBytes("data"));
                writer.Write(dataSize);
                for (int i = 0; i < count; i++)
                {
                    double phase = 2.0 * Math.PI * frequencyHz * i / sampleRate;
                    short sample = (short)Math.Round(Math.Sin(phase));
                    writer.Write(sample);
                }
            }
        }

        public void Dispose()
        {
            if (player != null)
            {
                try { player.Stop(); } catch { }
                player.Dispose();
                player = null;
            }
        }
    }

    public sealed class AppSettings
    {
        public bool Enabled { get; set; }
        public HotkeyDefinition TargetHotkey { get; set; }
        public int HoldMs { get; set; }
        public int CooldownMs { get; set; }
        public int PreSendDelayMs { get; set; }
        public bool AudioKeepAlive { get; set; }
        public int KeepAliveFrequencyHz { get; set; }
        public int KeepAliveSeconds { get; set; }
        public bool StatusSound { get; set; }
        public bool RunAtStartup { get; set; }
        public bool StartMinimized { get; set; }

        public AppSettings()
        {
            Enabled = true;
            TargetHotkey = new HotkeyDefinition(new List<int> { (int)Keys.LShiftKey }, (int)Keys.Z);
            HoldMs = 140;
            CooldownMs = 500;
            PreSendDelayMs = 120;
            AudioKeepAlive = true;
            KeepAliveFrequencyHz = 220;
            KeepAliveSeconds = 5;
            StatusSound = true;
            RunAtStartup = false;
            StartMinimized = true;
        }
    }

    public sealed class HotkeyDefinition
    {
        public List<int> Modifiers { get; set; }
        public int Key { get; set; }

        public HotkeyDefinition()
        {
            Modifiers = new List<int>();
        }

        public HotkeyDefinition(List<int> modifiers, int key)
        {
            Modifiers = modifiers ?? new List<int>();
            Key = key;
        }

        public HotkeyDefinition Clone()
        {
            return new HotkeyDefinition(new List<int>(Modifiers ?? new List<int>()), Key);
        }
    }

    internal static class HotkeyNames
    {
        public static bool IsModifier(int vk)
        {
            return vk == (int)Keys.ControlKey || vk == (int)Keys.LControlKey || vk == (int)Keys.RControlKey ||
                   vk == (int)Keys.ShiftKey || vk == (int)Keys.LShiftKey || vk == (int)Keys.RShiftKey ||
                   vk == (int)Keys.Menu || vk == (int)Keys.LMenu || vk == (int)Keys.RMenu ||
                   vk == (int)Keys.LWin || vk == (int)Keys.RWin;
        }

        public static int NormalizeModifier(int vk)
        {
            if (vk == (int)Keys.ControlKey || vk == (int)Keys.LControlKey || vk == (int)Keys.RControlKey) return (int)Keys.ControlKey;
            if (vk == (int)Keys.ShiftKey || vk == (int)Keys.LShiftKey || vk == (int)Keys.RShiftKey) return (int)Keys.ShiftKey;
            if (vk == (int)Keys.Menu || vk == (int)Keys.LMenu || vk == (int)Keys.RMenu) return (int)Keys.Menu;
            if (vk == (int)Keys.LWin || vk == (int)Keys.RWin) return (int)Keys.LWin;
            return vk;
        }

        public static string ToDisplayString(HotkeyDefinition hotkey)
        {
            if (hotkey == null) return "Not set";
            List<string> parts = new List<string>();
            if (hotkey.Modifiers != null)
            {
                if (hotkey.Modifiers.Contains((int)Keys.ControlKey) || hotkey.Modifiers.Contains((int)Keys.LControlKey) || hotkey.Modifiers.Contains((int)Keys.RControlKey)) parts.Add("Ctrl");
                if (hotkey.Modifiers.Contains((int)Keys.ShiftKey) || hotkey.Modifiers.Contains((int)Keys.LShiftKey) || hotkey.Modifiers.Contains((int)Keys.RShiftKey)) parts.Add("Shift");
                if (hotkey.Modifiers.Contains((int)Keys.Menu) || hotkey.Modifiers.Contains((int)Keys.LMenu) || hotkey.Modifiers.Contains((int)Keys.RMenu)) parts.Add("Alt");
                if (hotkey.Modifiers.Contains((int)Keys.LWin) || hotkey.Modifiers.Contains((int)Keys.RWin)) parts.Add("Win");
            }
            if (hotkey.Key != 0) parts.Add(KeyName(hotkey.Key));
            return parts.Count == 0 ? "Press a shortcut" : string.Join(" + ", parts.ToArray());
        }

        private static string KeyName(int vk)
        {
            Keys key = (Keys)vk;
            if (key >= Keys.A && key <= Keys.Z) return key.ToString();
            if (key >= Keys.D0 && key <= Keys.D9) return ((char)('0' + (vk - (int)Keys.D0))).ToString();
            if (key >= Keys.F1 && key <= Keys.F24) return key.ToString();
            switch (key)
            {
                case Keys.Space: return "Space";
                case Keys.Return: return "Enter";
                case Keys.Tab: return "Tab";
                case Keys.Escape: return "Esc";
                case Keys.Back: return "Backspace";
                case Keys.Delete: return "Delete";
                case Keys.Insert: return "Insert";
                case Keys.Home: return "Home";
                case Keys.End: return "End";
                case Keys.PageUp: return "Page Up";
                case Keys.PageDown: return "Page Down";
                case Keys.Left: return "Left";
                case Keys.Right: return "Right";
                case Keys.Up: return "Up";
                case Keys.Down: return "Down";
                case Keys.Oemcomma: return ",";
                case Keys.OemPeriod: return ".";
                case Keys.OemQuestion: return "/";
                case Keys.OemSemicolon: return ";";
                case Keys.OemQuotes: return "'";
                case Keys.OemOpenBrackets: return "[";
                case Keys.OemCloseBrackets: return "]";
                case Keys.OemPipe: return "\\";
                case Keys.OemMinus: return "-";
                case Keys.Oemplus: return "=";
                default: return key.ToString();
            }
        }
    }

    internal static class SettingsStore
    {
        public static readonly string AppFolder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HeadsetMicHotkey");
        private static readonly string SettingsPath = Path.Combine(AppFolder, "settings.json");

        public static AppSettings Load()
        {
            try
            {
                Directory.CreateDirectory(AppFolder);
                if (!File.Exists(SettingsPath))
                {
                    AppSettings first = new AppSettings();
                    first.RunAtStartup = StartupService.IsEnabled();
                    Save(first);
                    return first;
                }
                JavaScriptSerializer json = new JavaScriptSerializer();
                AppSettings settings = json.Deserialize<AppSettings>(File.ReadAllText(SettingsPath, Encoding.UTF8));
                if (settings == null) settings = new AppSettings();
                if (settings.TargetHotkey == null) settings.TargetHotkey = new AppSettings().TargetHotkey;
                if (settings.TargetHotkey.Modifiers == null) settings.TargetHotkey.Modifiers = new List<int>();
                settings.RunAtStartup = StartupService.IsEnabled();
                return settings;
            }
            catch (Exception ex)
            {
                Logger.Write("Settings load failed: " + ex.Message);
                return new AppSettings();
            }
        }

        public static void Save(AppSettings settings)
        {
            try
            {
                Directory.CreateDirectory(AppFolder);
                JavaScriptSerializer json = new JavaScriptSerializer();
                File.WriteAllText(SettingsPath, json.Serialize(settings), new UTF8Encoding(false));
            }
            catch (Exception ex)
            {
                Logger.Write("Settings save failed: " + ex.Message);
            }
        }
    }

    internal static class StartupService
    {
        private const string RunKey = "Software\\Microsoft\\Windows\\CurrentVersion\\Run";
        private const string ValueName = "HeadsetMicHotkey";

        public static bool IsEnabled()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(RunKey, false))
                    return key != null && key.GetValue(ValueName) != null;
            }
            catch { return false; }
        }

        public static void SetEnabled(bool enabled)
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(RunKey, true))
                {
                    if (key == null) return;
                    if (enabled)
                        key.SetValue(ValueName, "\"" + Application.ExecutablePath + "\" --startup");
                    else
                        key.DeleteValue(ValueName, false);
                }
            }
            catch (Exception ex)
            {
                Logger.Write("Startup setting failed: " + ex.Message);
            }
        }
    }

    internal static class Logger
    {
        private static readonly object Sync = new object();
        private static string LogFolder { get { return Path.Combine(SettingsStore.AppFolder, "logs"); } }

        public static void Write(string message)
        {
            try
            {
                lock (Sync)
                {
                    Directory.CreateDirectory(LogFolder);
                    string file = Path.Combine(LogFolder, "headset-hotkey-" + DateTime.Now.ToString("yyyyMMdd") + ".log");
                    File.AppendAllText(file, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + " " + message + Environment.NewLine);
                }
            }
            catch { }
        }

        public static void OpenFolder()
        {
            try
            {
                Directory.CreateDirectory(LogFolder);
                Process.Start("explorer.exe", LogFolder);
            }
            catch { }
        }
    }

    internal static class ThemeHelper
    {
        public static void Apply(Form form)
        {
            bool dark = IsDarkMode();
            Color back = dark ? Color.FromArgb(32, 32, 32) : Color.FromArgb(248, 249, 250);
            Color surface = dark ? Color.FromArgb(45, 45, 48) : Color.White;
            Color text = dark ? Color.FromArgb(245, 245, 245) : Color.FromArgb(30, 30, 30);
            Color border = dark ? Color.FromArgb(78, 78, 82) : Color.FromArgb(214, 218, 223);
            form.BackColor = back;
            form.ForeColor = text;
            ApplyControls(form.Controls, back, surface, text, border);
            NativeMethods.TrySetDarkTitleBar(form.Handle, dark);
        }

        private static void ApplyControls(Control.ControlCollection controls, Color back, Color surface, Color text, Color border)
        {
            foreach (Control control in controls)
            {
                control.ForeColor = text;
                if (control is Panel || control is TableLayoutPanel || control is FlowLayoutPanel) control.BackColor = back;
                if (control is Button)
                {
                    control.BackColor = surface;
                    Button b = (Button)control;
                    b.FlatAppearance.BorderColor = border;
                }
                if (control is NumericUpDown) control.BackColor = surface;
                ApplyControls(control.Controls, back, surface, text, border);
            }
        }

        private static bool IsDarkMode()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"))
                {
                    object value = key == null ? null : key.GetValue("AppsUseLightTheme");
                    return value is int && (int)value == 0;
                }
            }
            catch { return false; }
        }
    }

    internal static class NativeMethods
    {
        public const int WH_KEYBOARD_LL = 13;
        public const int WM_KEYDOWN = 0x0100;
        public const int WM_KEYUP = 0x0101;
        public const int WM_SYSKEYDOWN = 0x0104;
        public const int WM_SYSKEYUP = 0x0105;
        public const uint VK_MEDIA_PLAY_PAUSE = 0xB3;
        private const int INPUT_KEYBOARD = 1;
        private const uint KEYEVENTF_KEYUP = 0x0002;
        private const int SW_RESTORE = 9;
        public static readonly UIntPtr InjectedMarker = new UIntPtr(0x484D484B);

        public delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

        [StructLayout(LayoutKind.Sequential)]
        public struct KBDLLHOOKSTRUCT
        {
            public uint vkCode;
            public uint scanCode;
            public uint flags;
            public uint time;
            public UIntPtr dwExtraInfo;
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
            [FieldOffset(0)] public KEYBDINPUT ki;
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

        public static IntPtr SetKeyboardHook(LowLevelKeyboardProc callback)
        {
            using (Process process = Process.GetCurrentProcess())
            using (ProcessModule module = process.MainModule)
                return SetWindowsHookEx(WH_KEYBOARD_LL, callback, GetModuleHandle(module.ModuleName), 0);
        }

        public static void SendKey(ushort vk, bool keyUp)
        {
            INPUT[] input = new INPUT[1];
            input[0].type = INPUT_KEYBOARD;
            input[0].u.ki.wVk = vk;
            input[0].u.ki.wScan = 0;
            input[0].u.ki.dwFlags = keyUp ? KEYEVENTF_KEYUP : 0u;
            input[0].u.ki.time = 0;
            input[0].u.ki.dwExtraInfo = InjectedMarker;
            SendInput(1, input, Marshal.SizeOf(typeof(INPUT)));
        }

        public static void ShowExistingWindow()
        {
            try
            {
                IntPtr hwnd = FindWindow(null, "Headset Mic Hotkey");
                if (hwnd != IntPtr.Zero)
                {
                    ShowWindow(hwnd, SW_RESTORE);
                    SetForegroundWindow(hwnd);
                }
            }
            catch { }
        }

        public static void TrySetDarkTitleBar(IntPtr handle, bool dark)
        {
            try
            {
                int value = dark ? 1 : 0;
                DwmSetWindowAttribute(handle, 20, ref value, sizeof(int));
            }
            catch { }
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint threadId);
        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool UnhookWindowsHookEx(IntPtr hook);
        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wParam, IntPtr lParam);
        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr GetModuleHandle(string moduleName);
        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint SendInput(uint count, INPUT[] inputs, int size);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr FindWindow(string className, string windowName);
        [DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr hwnd, int command);
        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr hwnd);
        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
    }
}

