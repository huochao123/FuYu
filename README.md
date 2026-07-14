# 浮屿 FuYu

**一款停留在刘海下方、能听懂你并操作 Mac 的原生语音助手。**  
**A native voice assistant that lives below the Mac notch, talks naturally, and can help operate your Mac.**

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-111111?logo=apple)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)
![Native](https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-5E5CE6)
![License MIT](https://img.shields.io/badge/License-MIT-34C759)

[中文](#中文介绍) · [English](#english)

![浮屿设置中心](docs/images/settings.png)

## 中文介绍

浮屿是为 macOS 设计的轻量语音助手。它在空闲时完全隐藏，通过 Siri、全局快捷键或菜单栏唤醒；聆听、思考和回答时，以粒子动画和紧凑气泡显示当前状态。除了聊天，它还能把自然语言指令交给 Hermes / CUA，在用户可控的确认机制下操作 Mac。

![浮屿语音气泡](docs/images/voice-bubble.png)

### 真实皮肤画廊 / Live skin gallery

以下图片均直接截取自当前版本，不是概念图。六款皮肤都可以在“常规 → 悬浮入口皮肤”中即时切换。

All images below are captured from the current build. They are not concept renders. All six skins can be switched live from **General → Floating Skin**.

| 粒子声场 · Particle Field | 极光流体 · Aurora Flow |
| --- | --- |
| <img src="docs/images/voice-bubble.png" alt="粒子声场" width="410"> | <img src="docs/images/skin-auroraFlow.png" alt="极光流体" width="410"> |
| 经典圆球 · Classic Orb | 晶格脉冲 · Crystal Pulse |
| <img src="docs/images/skin-classicOrb.png" alt="经典圆球" width="410"> | <img src="docs/images/skin-crystalPulse.png" alt="晶格脉冲" width="410"> |

### 主要功能

- **原生悬浮交互**：默认位于刘海下方；空闲隐藏，唤醒后出现，不遮挡正常工作。
- **六款真实皮肤**：粒子声场、无框点波、经典圆球、极光流体、星轨共振和晶格脉冲。
- **状态动画**：聆听、思考、播报、完成与错误状态具有不同粒子动效。
- **气泡式字幕**：你说的话与 AI 回复直接显示在悬浮图标旁，不使用传统聊天窗口。
- **多种唤醒方式**：支持长按 Fn / 地球键、可修改的组合键、菜单栏，以及 `fuyu://listen` Siri 快捷指令。
- **多模型支持**：内置 MiMo、OpenAI、Claude、Gemini、DeepSeek、通义千问、Kimi、智谱 GLM、Ollama / LM Studio 与自定义兼容服务。
- **可切换语音识别**：Apple 本地、Apple 自动，以及 Apple 实时字幕 + MiMo ASR 最终校正的混合模式。
- **自然语音回复**：支持 macOS 离线声音、MiMo 云端音色、OpenAI TTS，并预留本地声音克隆接口。
- **上下文与本地记忆**：可调整上下文轮数；跨启动记忆默认关闭，开启后仅保存在本机。
- **Mac 操作能力**：可通过 Hermes / CUA 执行自然语言操作；操作前确认默认开启，也可由用户在高级设置中关闭。
- **隐私可控**：不包含遥测或广告；模型密钥、偏好和记忆不写入源码仓库。

### 系统要求

- macOS 15 或更高版本
- Apple Silicon Mac
- 麦克风与语音识别权限
- 使用 Mac 操作能力时需要相应辅助功能权限及 Hermes 环境
- 云端模型与云端语音功能需要用户自己的 API 密钥

> Hermes 是可选依赖。没有安装 Hermes 时，聊天、语音识别、语音回复、模型切换和记忆功能仍可正常使用；只有“控制 Mac”需要 Hermes。当前版本未实现其他操作执行后端。

### 安装

1. 从 Releases 下载最新 DMG。
2. 将“浮屿”拖入“应用程序”。
3. 首次启动时按需允许麦克风、语音识别和辅助功能权限。
4. 在“浮屿设置”中选择模型、语音与识别方式，并填写自己的 API 密钥。

当前仓库生成的是临时签名版本。正式公开分发前建议使用 Apple Developer ID 签名并完成公证。

### 使用 Siri 唤醒

在“快捷指令”中新建名为“开始说话”的快捷指令，添加“打开 URL”，并填入：

```text
fuyu://listen
```

之后说“嘿 Siri，开始说话”即可唤醒浮屿，避免 Siri 对“浮屿”同音词识别不稳定。

### 隐私与安全

- API 密钥保存在 `~/Library/Application Support/FuYu/credentials.json`，文件权限仅允许当前用户读写。
- 本地记忆保存在同一应用数据目录，不保存原始录音。
- 选择云端模型、云端 TTS 或 MiMo 混合识别时，相应文本或音频会发送给用户选择的服务商。
- Mac 操作确认默认开启。关闭后，模型判断为操作指令的请求会直接交给 Hermes 执行。
- `outputs/`、`work/`、个人配置、凭据、记忆和备份文件均被仓库规则排除。

详见 [PRIVACY.md](PRIVACY.md) 与 [SECURITY.md](SECURITY.md)。

### 从源码构建

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build
.build/debug/MiMoMac --self-test
scripts/package-app.sh
```

打包安装镜像：

```sh
scripts/create-installer.sh
```

### 参与贡献

欢迎提交问题、交互建议和代码改进。提交前请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

---

## English

FuYu is a lightweight native voice assistant for macOS. It stays completely hidden while idle and appears only when invoked through Siri, a global shortcut, or the menu bar. During listening, reasoning, and speaking, a compact particle glyph and speech bubble communicate the current state. FuYu can also route natural-language actions to Hermes / CUA to help operate the Mac under a user-controlled approval policy.

### Highlights

- **Native floating experience** — sits below the notch by default and disappears when idle.
- **Six live skins** — Particle Field, Bare Dot Wave, Classic Orb, Aurora Flow, Orbit Resonance, and Crystal Pulse.
- **State-aware motion** — distinct particle animations for listening, thinking, speaking, completion, and errors.
- **Speech-bubble captions** — live input and AI responses appear beside the assistant instead of inside a chat window.
- **Flexible invocation** — hold Fn/Globe, choose another global shortcut, use the menu bar, or invoke `fuyu://listen` from Siri Shortcuts.
- **Multiple model providers** — MiMo, OpenAI, Claude, Gemini, DeepSeek, Qwen, Kimi, GLM, Ollama / LM Studio, and custom compatible endpoints.
- **Selectable speech recognition** — Apple on-device, Apple automatic, or Apple live captions with MiMo ASR final correction.
- **Natural voice output** — macOS offline voices, MiMo cloud voices, OpenAI TTS, plus a reserved local voice-cloning endpoint.
- **Context and local memory** — configurable context length; persistent memory is opt-in and stored locally.
- **Mac actions** — Hermes / CUA integration with approval enabled by default and an advanced option to disable it.
- **Privacy-conscious** — no telemetry or advertising; credentials, preferences, and memory are never part of the source repository.

### Requirements

- macOS 15 or later
- Apple Silicon Mac
- Microphone and Speech Recognition permissions
- Accessibility permission and a working Hermes environment for Mac actions
- Your own API key for cloud models or cloud speech services

> Hermes is optional. Chat, speech recognition, voice output, model switching, and memory work without it. Hermes is required only for Mac actions. No alternative action backend is implemented in the current release.

### Install

1. Download the latest DMG from Releases.
2. Drag FuYu into Applications.
3. Grant only the permissions required by the features you use.
4. Open FuYu Settings to select a model, speech engine, recognition mode, and enter your own API key.

Repository builds are ad-hoc signed. Public distribution should use an Apple Developer ID signature and notarization.

### Wake with Siri

Create a Shortcut named **Start Talking**, add **Open URL**, and use:

```text
fuyu://listen
```

### Privacy & security

- API credentials are stored in `~/Library/Application Support/FuYu/credentials.json` with owner-only file permissions.
- Optional persistent memory stays in the application data directory; raw recordings are not retained.
- Cloud model, TTS, and hybrid ASR features send the required text or audio to the provider selected by the user.
- Mac action approval is enabled by default. Disabling it allows model-planned actions to be sent directly to Hermes.
- Build output, local work files, credentials, memory, and personal backups are excluded from version control.

See [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md) for details.

### Build from source

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build
.build/debug/MiMoMac --self-test
scripts/package-app.sh
```

To create the installer image:

```sh
scripts/create-installer.sh
```

### Contributing

Issues, interaction ideas, and code contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting a pull request.

---

FuYu is an independent open-source project and is not affiliated with Apple or any listed model provider.

## License / 许可证

FuYu is released under the [MIT License](LICENSE). / 浮屿采用 [MIT 许可证](LICENSE) 开源。
