# HeadsetMicHotkey

中文说明 | [English](README.md)

一个轻量的 Windows 托盘小工具，可以把耳机线控上的播放/暂停键映射成自定义快捷键。它最初是为了语音输入工作流做的：如果你的耳机麦克风离嘴比较近，就可以把耳机按钮变成一个顺手的语音输入触发键。

默认情况下，程序会把耳机播放/暂停键映射为 `左 Shift + Z`。

## 功能

- 常驻 Windows 系统托盘，不显示多余窗口
- 将耳机播放/暂停媒体键映射为可配置快捷键
- 通过静默音频保活，让耳机线控按钮更稳定
- 支持开机自启安装和卸载
- 日志保存在程序目录下，方便排查问题
- 便携式文件夹结构，换位置或换电脑也能用
- 托盘菜单支持暂停/启用、测试快捷键、打开配置、打开日志和退出

## 快速开始

1. 下载或克隆这个仓库。
2. 打开 `HeadsetButtonHotkey` 文件夹。
3. 双击 `start-headset-button-hotkey.cmd`。
4. 通过系统托盘图标暂停、测试、打开配置、打开日志或退出程序。

如果想在测试时看到控制台输出，可以运行：

```powershell
HeadsetButtonHotkey\start-headset-button-hotkey-visible.cmd
```

## 开机自启

为当前 Windows 用户安装开机自启：

```powershell
HeadsetButtonHotkey\install-startup.cmd
```

取消开机自启：

```powershell
HeadsetButtonHotkey\uninstall-startup.cmd
```

自启快捷方式会指向当前文件夹。如果你之后移动了程序文件夹，请在新位置重新运行一次 `install-startup.cmd`。

## 配置

编辑这个文件：

```text
HeadsetButtonHotkey\headset-button-config.json
```

默认配置：

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

支持的修饰键名称包括 `LShift`、`RShift`、`Shift`、`LCtrl`、`RCtrl`、`Ctrl`、`LAlt`、`RAlt` 和 `Alt`。

普通单字母按键也支持，例如 `Z`、`A`、`K`。

## 日志

日志会写入：

```text
HeadsetButtonHotkey\logs
```

日志文件夹不会被 Git 跟踪。

## 为什么需要音频保活

有些 3.5mm 耳机线控按钮并不是一个始终在线的普通键盘设备。在部分 Windows 声卡驱动上，播放/暂停键只有在音频会话唤醒耳机或音频端点之后才会稳定生效。

这个工具会在后台循环播放一个非常安静的自动生成 WAV 文件，用来保持音频链路活跃。如果你的耳机按钮不需要这个机制也能稳定工作，可以在配置里关闭：

```json
"audioKeepAlive": {
  "enabled": false
}
```

## 常见问题

如果托盘程序正在运行，但按耳机按钮没有反应：

- 确认没有同时运行旧的调试版或可见窗口版。
- 右键托盘图标，选择 `Test hotkey` 测试快捷键发送。
- 从托盘菜单打开日志文件夹，查看最新日志。
- 运行 `start-headset-button-hotkey-visible.cmd` 查看实时输出。
- 如果目标软件是管理员权限运行，这个工具也需要用管理员权限运行。

调试辅助脚本在 `tools` 文件夹中。

## 系统要求

- Windows
- PowerShell
- 标准 Windows 系统自带的 .NET Framework 相关程序集

不需要安装额外依赖。

## 许可证

MIT
