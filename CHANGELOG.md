# 更新日志 / Changelog

## v0.4.0 — 2026-07-15

### 可打断的自然语音交互 / Conversational voice interruption

- 浮屿朗读时可直接说话打断，并把新内容作为下一条指令继续处理。
- Hermes 执行中可以说“停一下”“先别执行”暂停，或直接追加修改；旧进程会被真实终止，再结合原任务重新规划。
- “可以了”“就这样”“执行吧”等明确结束语约 0.3 秒内提交；“然后”“还有”等未完语气会继续等待。
- 新增回声过滤与 macOS 语音处理，减少浮屿把自己的播报识别成用户抢话。
- 高级设置新增“允许说话打断”开关，默认开启。

- Speak over FuYu to stop a long response and continue with a new instruction.
- Pause or revise a running Hermes action; the old process is terminated before the original task and correction are re-planned.
- Explicit endings such as “go ahead” submit in about 0.3 seconds, while unfinished connectors keep listening.
- Added echo filtering and macOS voice processing to reduce self-transcription.
- Added an enabled-by-default **Allow voice interruption** setting.

### 可靠执行与授权 / Reliable execution and approval

- 复杂任务采用一次 Hermes 只读预案与一次模型审核，预审阶段禁止控制电脑，避免循环讨论和提前执行。
- 授权语音使用独立通道，“允许执行”“取消执行”不会再进入普通聊天或变成新命令。
- 授权窗口升级为与悬浮入口一致的粒子玻璃气泡，并持续监听明确授权口令。
- 模型或方案审核返回异常格式时会自动清理上下文并重试，而不是直接放弃任务。
- 应用退出前没有收到真实工具结果的任务会标记为中断或未验证。
- 普通应用打开命令、自然中文执行反馈、技术字符串过滤和真实结果回写得到加强。

- Complex actions use one read-only Hermes proposal and one bounded model review; preflight cannot control the Mac.
- Spoken approval uses a dedicated channel and never becomes a new conversation command.
- The approval panel now uses the same compact particle-and-glass visual language as the rest of FuYu.
- Malformed model or plan-review responses are automatically retried with clean context.
- Actions without a real result before app exit are marked interrupted or unverified.
- Improved generic app actions, natural Chinese result narration, technical-string filtering, and verified-result context.

## v0.3.1 — 2026-07-15

- 新增参考 Hermes USER.md 思路的永久习惯记忆：只保存用户明确要求记住的内容，与最近对话分开，并可在设置中查看、添加和删除。
- “记住……”“忘记……”和“你记住了什么”由本机直接处理，不依赖模型是否正确输出 JSON。
- 永久习惯会随每次模型请求提供给助手，支持跨重启保存，并限制条数与总长度，避免上下文无限膨胀。
- 模型返回缺字段、Markdown 代码块或兼容字段时自动补全与降级，不再轻易显示“无法解析”。
- 复杂 Mac 任务不再机械转发原话：浮屿会整理目标、约束和完成标准，Hermes 会先检查环境、规划步骤、执行并验证实际结果。

- Added explicit, locally stored permanent habit memory inspired by Hermes USER.md, separate from recent conversation history.
- “Remember”, “forget”, and “what do you remember” commands are handled locally and do not depend on model JSON output.
- Permanent habits are injected into each model request, persist across launches, and remain bounded in count and size.
- Added tolerant parsing for missing fields, fenced JSON, and common compatible response fields.
- Complex Mac tasks now carry goals, constraints, and acceptance criteria so Hermes can inspect, plan, execute, and verify instead of mechanically replaying the request.

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
