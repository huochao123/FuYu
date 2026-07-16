<div align="center">
  <img src="Resources/AppIcon.svg" width="108" alt="浮屿 FuYu 图标">
  <h1>浮屿 FuYu</h1>
  <p><strong>会听、会说、会照看 Mac 的原生桌面助手</strong></p>
  <p>语音对话、电脑管家、跨应用执行与飞书远程沟通，集中在一个有反馈、可确认的 macOS 界面里。</p>

  <p>
    <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-111827?logo=apple&logoColor=white">
    <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-native-0F766E">
    <img alt="Swift 6.2" src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white">
    <img alt="MIT License" src="https://img.shields.io/badge/License-MIT-22C55E">
  </p>

  <p>
    <a href="https://github.com/huochao123/FuYu/releases">下载最新版</a>
    · <a href="#核心能力">核心能力</a>
    · <a href="#安装">安装</a>
    · <a href="CHANGELOG.md">更新日志</a>
    · <a href="PRIVACY.md">隐私说明</a>
    · <a href="#english">English</a>
  </p>
</div>

![浮屿 0.5 电脑管家主界面](docs/images/fuyu-0.5-dashboard.png)

## 不只是一个聊天窗口

浮屿是一款面向 Apple Silicon Mac 的原生助手。它可以停留在刘海下方，通过语音、快捷键、文字或飞书接收要求；MiMo 负责理解和选择能力，电脑维护由浮屿本机工具直接完成，只有本机工具覆盖不到的复杂跨应用任务才交给 Hermes。

浮屿知道自己是一款以 Mac 为核心的本机助手，也会按当前电脑动态了解自己的能力。电脑管家的真实检测结果会同步到 AI 上下文，因此检测后可以直接问“哪个最需要处理”“这条建议有什么好处”或“确认执行”，无需重新描述结果。

| 语音助手 | 本机电脑管家 | 远程与自动化 |
| --- | --- | --- |
| 声音联动光场、实时字幕、自然播报 | 系统体检、垃圾扫描、文件整理 | 飞书 WebSocket 远程对话 |
| 长按 Fn / 地球键、Siri、菜单栏唤醒 | 大文件、重复文件、启动项、应用残留 | Hermes 处理复杂跨应用任务 |
| 可随时关闭识别，双击悬浮入口停止误识别 | 持续高负载与发热进程判断 | 修改 Mac 前保留本机确认 |

## 核心能力

### 本机优先的 Agent 核心

浮屿不是把所有命令转发给 Hermes 的外壳。它使用统一决策协议区分三种结果：直接回答、调用浮屿本机工具、委派 Hermes 专家任务。MiMo 可以看到真实工具清单和最近检测结果；本机快速路由则保证常见 Mac 操作不必等待云端模型。

- “下载文件夹分析下”“大文件多吗”“检查启动项”直接调用本机扫描器。
- 工具结果同时进入状态屏、聊天记录和后续 AI 上下文，可以继续问原因、收益或下一步。
- “为什么刚才超时”只读取运行记录并解释，不会再次执行或进入复杂任务预审。
- 云端模型超时时，本机电脑管家、系统控制、监控通知和已有结果仍可使用。
- 清理、移动等修改操作必须先展示真实扫描结果、收益与风险，再等待明确确认。

### 一个真正可用的主界面

- 左侧是声音联动光场、语音状态和直接控制区；右侧承载对话与电脑管家。
- 三套主界面主题：深海蓝青、暖金石墨、冰川银蓝。
- 采用分层磨砂玻璃与 Liquid Glass 风格，并为旧系统提供原生材质回退。
- 功能卡片支持整卡点击、鼠标悬停高亮、按下缩放、执行动画和完成状态，不让操作“悄悄发生”。
- 状态屏完整展示每次扫描的数量与逐条明细；内容较多时在屏幕内部滚动，不必前往聊天记录。
- 每项结果同时给出优化收益、风险和明确的确认执行／暂不处理选项，执行后继续在状态屏验证实际结果。

### 不绕模型的本机电脑管家

九项基础工具直接读取本机状态，不消耗模型额度，也不经过 Hermes：

- 系统体检
- 垃圾清理预览
- 下载文件夹智能整理预览
- 大文件扫描
- 重复文件哈希确认
- 启动项检查
- 发热进程持续负载判断
- 应用残留扫描
- 性能与存储优化建议

所有涉及清理和移动的操作都遵循 **先扫描 → 看预览 → 明确确认 → 移到废纸篓**。浮屿不会因为点了一张卡片就直接删除文件。

常用系统控制同样采用本机优先：音量和静音可直接调整；屏幕亮度会先检测当前 Mac 是否提供可靠接口。只有得到真实系统结果才会显示成功，不支持时会明确说明。发热进程监控可主动低开销检查，但不会擅自结束进程、清理或移动文件。

### 更安静、更可控的语音

- 支持 Apple 本地识别、自动识别和 MiMo 混合校正。
- 启用 Apple Voice Processing，降低电脑视频和浮屿自身播报造成的回声误识别。
- 主界面可直接关闭语音识别；识别中关闭会立即停止且不发送。
- 悬浮入口双击可结束当前识别，不提交误触内容。
- 支持打断播报、暂停任务和追加修改要求。

文字、语音和系统提醒采用三套独立交互：文字聊天不会弹出悬浮窗或启动麦克风；语音继续使用声音动画与朗读；真实监控异常使用短暂的纯文字悬浮通知，不监听也不朗读。

### 飞书远程入口

通过独立的飞书企业自建应用和 WebSocket 长连接，可以在外面直接与浮屿对话，不需要额外部署公网服务器。聊天回复可直接返回；清理、移动文件和系统修改仍会在 Mac 上等待确认。

### 多模型、记忆与人格

- 支持 MiMo、OpenAI、Claude、Gemini、DeepSeek、通义千问、Kimi、智谱 GLM、Ollama / LM Studio 与自定义兼容接口。
- 采用与成熟 Agent 类似的四层记忆：最近对话原文、当前任务状态、永久习惯、完整会话归档与相关历史检索。
- “去吧、继续、为什么、刚才那个”等短句会承接当前任务；任务状态与相关历史可跨应用重启恢复。
- 只有明确要求“记住”的稳定偏好才进入永久习惯；临时任务保留在会话归档中，避免污染长期记忆。
- 支持自定义人格、关系、背景和说话方式。
- 可预览并导入 SillyTavern Character Card V1/V2、常见 PNG 角色卡和提示词预设。

## 同一套视觉语言

主界面和设置中心使用一致的深海背景、玻璃卡片、圆角、间距与按压反馈。设置不再像另一个独立工具。

![浮屿新版设置中心](docs/images/settings.png)

浮屿还提供六款悬浮入口皮肤，可在设置中即时切换：

| 粒子声场 | 极光流体 | 经典圆球 |
| --- | --- | --- |
| <img src="docs/images/voice-bubble.png" alt="粒子声场" width="300"> | <img src="docs/images/skin-auroraFlow.png" alt="极光流体" width="300"> | <img src="docs/images/skin-classicOrb.png" alt="经典圆球" width="300"> |

## 安全与隐私

- 不包含广告或遥测。
- 不保存原始录音。
- 模型密钥、偏好和本地记忆不会写入源码仓库。
- 电脑管家扫描在本机完成；Hermes 只用于复杂跨应用任务。
- Hermes 是可选依赖。没有 Hermes 时，聊天、语音、记忆与电脑管家仍可使用。
- 云端模型、云端 TTS 或混合 ASR 只会把完成相应功能所需的数据发送给用户选择的服务商。

详见 [隐私说明](PRIVACY.md) 与 [安全说明](SECURITY.md)。

## 系统要求

- macOS 15 或更高版本
- Apple Silicon Mac
- 使用语音时需要麦克风和语音识别权限
- 复杂跨应用控制需要辅助功能权限与 Hermes 环境
- 云端模型或语音服务需要用户自己的 API 密钥

## 安装

1. 前往 [Releases](https://github.com/huochao123/FuYu/releases) 下载最新 DMG。
2. 将“浮屿”拖入“应用程序”。
3. 首次启动时，只允许实际需要的权限。
4. 在设置中选择模型、语音与识别方式。

当前公开构建使用临时签名。正式大范围分发前仍建议使用 Apple Developer ID 签名并完成公证。

## Siri 唤醒

在“快捷指令”中新建名为“开始说话”的快捷指令，添加“打开 URL”，填入：

```text
fuyu://listen
```

之后说“嘿 Siri，开始说话”即可唤醒浮屿。

## 从源码构建

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build
.build/debug/MiMoMac --self-test
scripts/package-app.sh
scripts/create-installer.sh
```

## 开源组件与参考

- 安全缓存扫描、白名单路径校验、移到废纸篓和本机清理日志集成 [Dusty CleanerEngine](https://github.com/yagcioglutoprak/dusty)（MIT），许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
- 实时状态屏与后台采样的功能设计参考 [Stats](https://github.com/exelban/stats)；浮屿使用自己的轻量采样与连续高负载判断。
- [Mole](https://github.com/tw93/mole) 仅作为产品与安全边界参考，没有合并其 GPLv3 代码。

欢迎提交 Issue、交互建议与代码改进。参与前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

---

## English

**FuYu is a native voice assistant and local Mac care console for Apple Silicon.** It combines a sound-reactive voice interface, shared conversation, local maintenance tools, Feishu remote messaging, and optional Hermes-powered cross-app actions in one feedback-rich macOS experience.

### Highlights

- Explicit Agent decisions for direct replies, native Mac tools, and optional Hermes expert delegation; common local actions do not wait for Hermes.
- Native SwiftUI + AppKit experience with glass materials and three main-window themes.
- Local Mac Care: health inspection, safe junk preview, Downloads organization preview, large files, duplicates, login items, hot processes, leftovers, and optimization advice.
- Full-card hit targets with hover, press, running, completion, and failure feedback.
- Voice master switch, echo suppression, interruption, Fn/Globe push-to-talk, Siri Shortcut URL, and double-click cancellation.
- Feishu WebSocket channel for remote conversation with local approval retained for Mac changes.
- MiMo, OpenAI, Claude, Gemini, DeepSeek, Qwen, Kimi, GLM, Ollama / LM Studio, and custom compatible providers.
- Layered local memory, custom personas, and SillyTavern character/preset import.
- No telemetry or ads. Hermes is optional and reserved for complex cross-app actions.

### Requirements and install

Requires macOS 15+ on Apple Silicon. Download the latest DMG from [Releases](https://github.com/huochao123/FuYu/releases), drag FuYu into Applications, and grant only the permissions required by the features you use.

See [PRIVACY.md](PRIVACY.md), [SECURITY.md](SECURITY.md), [CHANGELOG.md](CHANGELOG.md), and [ROADMAP.md](ROADMAP.md).

---

FuYu is an independent open-source project and is not affiliated with Apple or any listed model provider. Released under the [MIT License](LICENSE).
