# HeadsetMicHotkey

中文说明 | [English](README.md)

一个轻量的 Windows 耳机线控快捷键工具，可以把耳机上的播放/暂停键映射成任意自定义键盘快捷键。它最初是为语音输入场景做的：耳机麦克风离嘴比较近时，可以直接用线控按钮快速触发语音转文字。

当前推荐版本为 **v2.0.1**。新版已经从原来的 CMD + PowerShell 脚本升级为真正的 Windows GUI 程序：没有命令提示符窗口，不需要手动编辑配置文件，关闭主窗口后只保留系统托盘图标。

## 下载

**推荐直接下载已经编译好的 EXE：**

[下载 HeadsetMicHotkey.exe](dist/HeadsetMicHotkey.exe?raw=1)

无需安装。下载后直接双击运行即可。

> 由于目前没有购买商业代码签名证书，Windows 第一次运行时可能提示“未知发布者”或出现 SmartScreen 提示。这不影响程序本身的功能。

## v2.0.1 主要功能

- 真正的 Windows GUI EXE，不再依赖 CMD / PowerShell 作为运行宿主
- 无控制台黑框、无最小化命令提示符窗口
- 关闭主窗口后自动隐藏到 Windows 系统托盘
- 双击托盘图标重新打开主界面
- 单实例运行，避免重复启动多个键盘 Hook
- 直接在界面中录制自定义快捷键
- 支持 Ctrl / Shift / Alt / Win 等组合键
- 支持 F8、Space 等单独按键
- 内置 **Test**，无需按耳机按钮也能测试当前快捷键
- 音频保活开关，提高部分 3.5 mm 耳机线控的稳定性
- 一键设置开机自启
- 设置自动保存，无需手改 JSON
- 自动适配 Windows 明暗主题
- AI + 麦克风应用图标
- 日志记录与快捷键注入诊断
- 修正 Win32 `SendInput` 结构，并加入兼容回退逻辑
- EXE 体积非常小，使用系统已有的 .NET Framework 运行环境

默认映射仍然是：

```text
耳机播放/暂停键  ->  Shift + Z
```

## 快速使用

1. 下载上面的 `HeadsetMicHotkey.exe`。
2. 双击运行。
3. 如果默认的 `Shift + Z` 不适合你，点击 **Record new hotkey**。
4. 在键盘上直接按你想设置的新快捷键。
5. 按耳机线控的播放/暂停键即可触发。
6. 配置完成后可以直接关闭主窗口，程序会继续在系统托盘运行。

主界面里保留了最常用的几个功能：

- **Mapping**：启用或暂停耳机按键映射
- **Audio keep-alive**：开启或关闭音频保活
- **Run at startup**：设置 Windows 开机自动运行
- **Record new hotkey**：录制新的快捷键
- **Test**：直接测试当前快捷键
- **Advanced**：调整延迟、按键保持时间、冷却时间和音频保活参数

## 自定义快捷键

新版不需要编辑 JSON。点击 **Record new hotkey** 后直接在键盘上按新的组合即可。

例如可以设置为：

```text
Shift + Z
Ctrl + Shift + M
Ctrl + Alt + Space
Win + Shift + S
F8
Space
```

设置保存后，下次启动会自动恢复。

## 系统托盘

点击主窗口右上角关闭按钮时，程序不会退出，而是隐藏到 Windows 通知区域。

右键托盘图标可以：

- 打开主界面
- 暂停 / 启用映射
- 测试当前快捷键
- 打开日志文件夹
- 完全退出程序

双击托盘图标可以重新打开主窗口。

## 音频保活

有些 3.5 mm 耳机线控按钮并不是始终在线的普通键盘设备。在部分声卡和驱动环境中，音频端点进入休眠后，播放/暂停按键可能不再稳定上报。

HeadsetMicHotkey 可以在后台生成并循环播放一个极低幅度的 WAV 信号，用来保持相关音频链路活跃。

如果你的耳机不需要这一机制也能稳定使用，可以直接在主界面关闭 **Audio keep-alive**。

## 设置与日志位置

新版把设置和日志放在用户目录里，因此以后直接用新 EXE 覆盖旧 EXE，一般不会丢失原来的设置。

程序数据目录：

```text
%LocalAppData%\HeadsetMicHotkey\
```

日志目录：

```text
%LocalAppData%\HeadsetMicHotkey\logs\
```

日志会记录耳机按键是否被检测到、程序是否尝试发送快捷键以及快捷键注入情况，方便定位问题。

## 常见问题

如果界面能检测到耳机按钮，但目标软件没有响应：

1. 先点击 **Test**。如果 Test 能触发目标软件，说明快捷键输出链路基本正常。
2. 确认你手动按同样的快捷键时，目标软件确实能够响应。
3. 从托盘菜单打开日志文件夹，查看当天最新日志。
4. 确认没有同时运行旧版本或另外一个 HeadsetMicHotkey。
5. 如果目标软件以管理员权限运行，可以尝试让 HeadsetMicHotkey 使用相同权限运行。

v2.0.1 已经针对快捷键“检测到了但没有真正发送”的问题修正了 Win32 `SendInput` 数据结构，并加入兼容回退。

## 源码与自动构建

普通用户**不需要自己编译**。

当前 GUI 版本源码位于：

```text
HeadsetMicHotkeyV2/
```

技术栈：

```text
C# + Windows Forms + .NET Framework 4.8 + Win32 API
```

GitHub Actions 会自动在 Windows 环境中编译 Release 版本，并生成可直接运行的 EXE。应用图标也会在构建时自动生成并嵌入程序。

如果需要本地编译，可以使用 Visual Studio 或 MSBuild 打开 `HeadsetMicHotkey.csproj`，构建 `Release` 配置即可。

## 旧版

原来的 PowerShell/CMD 版本仍保留在：

```text
HeadsetButtonHotkey/
```

它主要用于保留历史实现和调试参考。现在推荐直接使用新版 GUI EXE。

## 许可证

MIT
