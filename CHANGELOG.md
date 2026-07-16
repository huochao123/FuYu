# 更新日志 / Changelog

## v0.6.0 — 2026-07-16

- 浮屿拥有明确的本机助手身份和动态能力清单，能准确说明自己能做什么、哪些操作需要确认，以及何时才需要 Hermes。
- 聊天与电脑管家共享结构化检测结果；用户可在检测后直接追问异常、收益、风险和下一步，不必重新查找聊天记录。
- 系统体检、垃圾扫描、智能整理、大文件、重复文件、启动项、发热进程、应用残留和优化建议均可由 AI 直接调用本机工具。
- 音量、静音等可逆系统设置优先本机直达；屏幕亮度按运行时真实能力检测，不支持时明确说明，不虚报执行成功。
- 本机检测和控制不再转交 Hermes；跨应用复杂任务仍由 Hermes 负责规划和验证。
- 发热监控继续低开销主动检查并只在持续异常时通知；清理、移动和其他有影响的操作仍必须明确确认。
- 新增身份能力、共享结果、本机指令路由及危险操作不直删等自动化自检。

- FuYu now has an explicit Mac-first identity and a runtime capability manifest.
- Chat and Mac Care share structured results, enabling direct follow-up analysis and local actions.
- Nine maintenance tools plus volume and mute control use a local-first execution path instead of Hermes.
- Brightness support is detected honestly at runtime; unsupported displays never produce a false success claim.
- Proactive monitoring remains read-only, while cleanup and file moves still require explicit approval.

## v0.5.3 — 2026-07-16

- 九项电脑管家工具加入完整执行闭环：检测结果、预期收益、风险说明、确认执行、暂不处理与执行后验证。
- 安全缓存可确认后移到废纸篓；下载文件可确认后按类型真实整理，避免覆盖同名文件。
- 大文件、重复文件和应用缓存可直接在 Finder 定位；启动项打开系统设置；发热进程打开活动监视器。
- 优化建议不再是静态文字，而是连接到垃圾扫描、长期下载文件定位和高负载进程检查等真实动作。
- 文字、语音与系统通知拆分为三种独立交互：文字只留在聊天页；语音继续使用悬浮窗与麦克风；异常通知只显示文字，不监听也不朗读。
- 发热监控使用真实进程采样，连续三次高 CPU 才提醒；监控连续失败三次也会发出纯文字异常通知。
- 电脑管家自检升级为九项真实扫描、发热进程采样与临时文件实际整理验证。

- Added a complete detect, explain, confirm, execute, and verify loop to all nine Mac Care tools.
- Safe caches can be moved to Trash after confirmation; Downloads organization performs real collision-safe file moves.
- Finder, Login Items, and Activity Monitor actions connect read-only findings to safe next steps.
- Text, voice, and system notifications are now separate interaction channels.
- Thermal alerts use real process samples and require three consecutive high-CPU readings.

## v0.5.2 — 2026-07-16

- 电脑管家状态屏不再只显示一句结论：完整展示本次扫描返回的所有明细。
- 启动项会直接显示发现总数与每一项名称；大文件、重复文件、发热进程、应用残留和优化结果同样逐条展示。
- 结果较多时在状态屏内部滚动，并支持复制文字；无需切换到聊天记录。
- 结果、授权、清理确认、停止和返回总览全部留在电脑管家界面完成。

- Mac Care now shows every returned result row instead of only a summary.
- Login items, large files, duplicates, hot processes, leftovers, and optimization details remain inside the dashboard with internal scrolling and selectable text.
- Results, approvals, cleanup confirmation, stopping, and returning to live metrics no longer require the chat view.

## v0.5.1 — 2026-07-16

- 电脑管家卡片改为整卡点击，新增悬停发光、按压缩放、高光反馈以及明确的开始、停止和完成状态。
- 检测期间再次点击当前卡片可停止；点击其他工具会显示正在进行的任务，不再无声忽略操作。
- 状态总览升级为电脑管家的主屏幕：待机时显示 Mac 实时状态，运行时原地切换为进度屏，完成后直接显示结果与下一步操作。
- 清理确认、Hermes 操作授权、取消与返回总览均可在状态屏中完成，不必切换到聊天页面。
- 调整视觉比例，扩大状态屏并压缩九个功能按钮，让屏幕成为信息主角、按钮成为清晰的控制区。
- 设置中心统一为主界面的深海液态玻璃风格，按钮加入一致的按压、亮度和弹性动画反馈。
- 悬浮气泡、授权、停止和历史等关键按钮补齐即时按压动画。
- 重做 GitHub 项目首页，更新真实主界面和设置截图，按产品能力、隐私、安装与开源组件重新组织内容。

- Made every Mac Care card fully clickable with hover glow, press scaling, highlight feedback, and explicit start/stop/completion states.
- The dashboard now acts as the Mac Care screen: live metrics while idle, in-place progress while running, and results plus next actions when complete.
- Cleanup confirmation and action approval can be completed directly in the dashboard without switching to chat.
- Rebalanced the layout around a larger status screen and smaller tool controls.
- Unified Settings with the main window's deep-ocean glass language and consistent button motion.
- Rebuilt the GitHub landing page around the current product and real screenshots.

## v0.5.0 — 2026-07-16

- 新增完整主界面：声音能量联动光场、共享对话与电脑管家控制台。
- 新增系统体检、垃圾扫描、智能整理、大文件、重复文件、启动项、发热进程、应用残留与优化建议入口。
- 所有维护工具新增分析、执行、完成和失败动画，并坚持先扫描预览、再由用户确认修改。
- 在支持的系统上采用原生 Liquid Glass；旧版 macOS 自动回退到磨砂材质。
- 新增飞书远程设置与 WebSocket 桥接，凭证保存于钥匙串，远程 Mac 操作继续等待本机批准。
- 主对话窗口新增语音识别总开关与“停止识别”，误触停止不会提交内容；悬浮入口识别中双击也可立即停止。
- 麦克风启用系统回声消除并采用最低媒体压低等级，识别结束后立即释放语音处理，避免 Fn 触发后持续影响播放音量。
- 主界面升级为分层蓝紫内容底与独立功能面板，主要控件采用磨砂 Liquid Glass 胶囊按钮，电脑管家按核心维护与专项工具重新分区。
- 电脑管家九项扫描改为本机直接执行，不再经过模型或 Hermes；安全清理采用 Dusty 的 MIT 许可白名单引擎，预览确认后移到废纸篓并保留本机操作记录。
- 新增后台发热进程监测：每 12 秒低开销采样，连续三次高 CPU 才提示，区分短时波动与持续高负载；只提醒，不擅自结束进程。
- 重绘蓝青浮岛声波应用图标；主界面新增深海蓝青、暖金石墨、冰川银蓝三套即时切换皮肤，减少通用紫色 AI 视觉。
- 电脑管家改为六张状态卡、三张核心维护大卡和 3×2 专项工具宫格，扩大窗口与卡片留白，解决按钮拥挤和列表感过重。
- 状态总览进一步合并为一块实时仪表屏，显示健康度、CPU、内存、进程数、最高负载进程、磁盘、开机时间、发热风险以及语音和远程通道状态；与下方可点击功能卡明确区分。

- Added a full main window with a sound-reactive field, shared conversation, and a dedicated Mac Care console.
- Added system inspection, junk scanning, smart organization, large/duplicate file discovery, login-item review, hot-process analysis, app-leftover scanning, and optimization guidance.
- Added analyzing, executing, completed, and failed animation states with preview-before-change safety.
- Uses native Liquid Glass when available with a frosted-material fallback on older macOS releases.
- Added Feishu remote settings and a WebSocket bridge; credentials live in Keychain and remote Mac actions still require local approval.
- Added a voice-recognition master switch and cancel-without-submit action in the main conversation window; double-clicking the floating entry also cancels active recognition.
- Enabled acoustic echo cancellation with minimum media ducking and immediate voice-processing teardown after recognition.
- Refined the main window with layered indigo content surfaces, frosted Liquid Glass action capsules, and clearer Mac Care sections.
- All nine Mac Care scans now run locally without a model or Hermes; safe cleanup uses Dusty's MIT-licensed allowlist engine, confirms a preview, moves items to Trash, and writes a local action log.
- Added low-overhead hot-process monitoring every 12 seconds; alerts require three consecutive high-CPU samples, separating brief spikes from sustained load without terminating processes automatically.
- Replaced the generic purple icon with a teal floating-island waveform mark and added Deep Ocean, Warm Graphite, and Glacier themes.
- Rebuilt Mac Care around six status cards, three primary maintenance tiles, and a 3×2 specialist-tool grid with more spacing.
- Consolidated status into one live dashboard screen with health score, CPU, memory, process count, busiest process, disk, uptime, heat risk, voice, and remote-channel state.

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
