# 更新日志 / Changelog

## v0.3.0 — 2026-07-15

### 新功能 / Added

- 将大型 Mac 任务面板替换为 430 × 82 的紧凑执行气泡，尺寸与语音气泡一致。
- 执行气泡显示“正在连接 Hermes”“Hermes 已接收任务”“正在检查结果”等真实阶段，并保留当前皮肤动画、动态进度和停止控件。
- 设置中心新增“聊天”页面，可直接输入文字并与语音共享上下文；文字输入默认不会触发朗读。
- 文字聊天记录统一显示用户消息、AI 回复、等待授权、Hermes 执行、成功和失败结果。
- 新增本机功能自检，显示语音权限、模型配置、Hermes 状态和操作确认状态。
- Hermes 任务超过两分钟仍未结束时自动停止并记录失败原因，避免执行气泡永久停留。
- GitHub 首页新增从真实运行版本录制的执行气泡动画。

- Replaced the large Mac task panel with a compact 430 × 82 execution bubble matching the voice interface.
- Added visible Hermes stages, active skin motion, animated progress, and a compact stop control.
- Added a text chat page that shares context with voice while remaining silent by default.
- Unified user, assistant, approval, Hermes, success, and failure events in the chat history.
- Added local diagnostics for speech permissions, model configuration, Hermes availability, and action approval.
- Stops and records Hermes tasks that remain stuck for more than two minutes.
- Added a real in-app execution animation to the GitHub project page.

### 修复与稳定性 / Fixed & stability

- 修复极光流体皮肤持续刷新导致的主线程崩溃。
- 修复新版 macOS 不允许自定义 URL 作为 `NSUserActivity.webpageURL` 而导致的启动崩溃。
- 语音识别或麦克风链路意外中断时重建录音资源并有限次数自动重连。
- 长回答在智能语音模式下会生成一句可朗读摘要，不再出现有文字但没有声音。
- 菜单栏点阵运行图标保持常驻，并显示待命、聆听、思考、执行、说话和异常状态。

- Fixed a main-thread crash caused by nested Aurora Flow animation updates.
- Fixed a launch crash on newer macOS builds caused by assigning a custom scheme to `NSUserActivity.webpageURL`.
- Rebuilds speech resources and retries a limited number of times after recognition interruptions.
- Generates a speakable summary for long replies instead of silently skipping voice output.
- Keeps the dot-orbit menu-bar health indicator visible with state-specific feedback.

### 对话、人格与兼容 / Conversation, personas & compatibility

- 新增可查看的本轮聊天与 Mac 操作记录。
- Hermes 的真实成功或失败结果会写回上下文，可继续追问“刚才完成了吗”。
- 新增操作意图二次校验，减少模型口头答应但没有调用工具的情况。
- 新增角色名称、关系、背景、性格和说话方式设置。
- 支持预览并导入 SillyTavern Character Card V1/V2 JSON、常见 PNG 内嵌卡和提示词预设；支持替换或合并。

- Added visible session and Mac-action history.
- Writes real Hermes success or failure results back into context for follow-up questions.
- Added a second action-intent check to reduce false promises without tool execution.
- Added custom names, relationships, backgrounds, traits, and speaking styles.
- Added preview/import for SillyTavern Character Card V1/V2 JSON, common embedded PNG cards, and prompt presets with replace/merge choices.

## v0.2.1 — 2026-07-15

- 菜单栏状态图标改为常驻显示。 / Kept the menu-bar status indicator visible.

## v0.2.0 — 2026-07-15

- 首次加入聊天记录、真实操作结果、人设、酒馆导入和稳定性修复。 / Added conversation history, real action results, personas, Tavern imports, and stability fixes.

## v0.1.0

- 首个公开版本。 / Initial public release.
