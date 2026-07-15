# 浮屿路线图 / FuYu Roadmap

这份路线图区分“当前已经可用”与“后续计划”，避免把方向讨论写成已经完成的功能。

This roadmap separates what works today from planned work so product direction is never presented as a shipped capability.

## 已实现 / Available now

- 会话上下文与可选的本机跨启动记忆。
- Hermes 操作前确认、执行状态记录，以及真实成功/失败结果回写上下文。
- 操作意图二次校验，减少“口头答应但没有执行”的情况。
- 可查看的本轮聊天与操作记录。
- 自定义人格、关系、背景、性格和说话方式。
- SillyTavern Character Card V1/V2 JSON、常见 PNG 内嵌卡与提示词预设的本机预览导入。
- 复杂任务的一次只读预案、一次审核、真实执行与结果验证。
- 朗读抢话、执行中暂停或修改，以及明确结束语快速提交。
- 独立语音授权、异常格式自动恢复和中断任务标记。

- Conversation context and optional local persistent memory.
- Pre-action approval, visible execution status, and real Hermes results written back into context.
- A second action-intent check to reduce false “I’ll do it” replies.
- Visible conversation and action history for the current session.
- Custom personas, relationships, backgrounds, traits, and speaking styles.
- Local preview/import for SillyTavern Character Card V1/V2 JSON, common embedded PNG cards, and prompt presets.
- A bounded read-only proposal, review, real execution, and result verification path for complex actions.
- Speech barge-in, pause/revise during execution, and fast submission for explicit end-of-turn phrases.
- Dedicated spoken approval, malformed-response recovery, and interrupted-task records.

## 下一阶段：任务状态 / Next: task state

- 为每项操作保存独立任务记录：目标、计划、当前步骤、工具输出、失败原因与最终验证结果。
- 回答“刚才完成了吗”“为什么失败”“继续上一步”前，优先读取任务状态，而不只依赖聊天文字。
- 为未完成、部分完成、已完成和无法验证建立明确状态，禁止把“已经规划”说成“已经完成”。
- 增加本地声纹注册与说话人验证，在视频播放和多人环境中只接受已登记用户；该功能必须提供误识别测试和随时关闭选项。

- Track each action as a structured task: goal, plan, current step, tool output, failure reason, and verification result.
- Read task state before answering “Did it finish?”, “Why did it fail?”, or “Continue the last step?” instead of relying only on chat text.
- Distinguish planned, running, partially complete, complete, failed, and unverified states.
- Add local speaker enrollment and verification so background video or other speakers can be ignored, with measurable false-match testing and an off switch.

## 智能体闭环 / Agent loop

目标流程：**理解目标 → 必要时澄清 → 制订计划 → 执行一步 → 观察结果 → 重试或改计划 → 验证 → 汇报**。

Target loop: **understand → clarify when needed → plan → execute one step → observe → retry or re-plan → verify → report**.

- 建立工具注册表，让模型知道每个执行后端能做什么、需要什么权限、返回什么证据。
- 操作失败时根据真实错误选择安全重试、换路径或向用户说明阻塞原因。
- 完成后做轻量验证，例如检查应用是否打开、文件是否存在或设置是否生效。
- 高风险步骤继续由用户确认；低风险只读检查可以作为验证动作。

## 记忆升级 / Memory evolution

- 将短期对话、任务记录、长期偏好分开保存。
- 增加记忆压缩与去重，保留事实、决定和未完成事项，减少无意义上下文消耗。
- 提供可查看、可修改、可删除的记忆管理界面。
- 人格记忆与工具事实分层，角色扮演不能改写真实执行结果。

## 酒馆兼容后续 / Future Tavern compatibility

- 角色库与快速切换，而不只维护一个当前角色。
- 用户 Persona、World Info / Lorebook 与更完整的角色卡扩展字段映射。
- 导出为兼容角色卡，以及对话开场白和示例的独立管理。
- 群聊、脚本和第三方扩展只有在能给出明确兼容边界与安全模型后再考虑。

## 原则 / Principles

- 真实结果优先于模型措辞。
- 不确定时显示不确定，不伪造完成状态。
- 自动化越强，状态、证据、撤销能力和权限边界越要清楚。
- 功能说明只描述经过测试的实际能力。

- Tool results take precedence over model wording.
- Uncertainty remains visible; completion is never fabricated.
- More autonomy requires clearer state, evidence, undo paths, and permissions.
- Public documentation describes tested behavior only.
