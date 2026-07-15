# 隐私说明 / Privacy

## 中文

浮屿不包含广告、用户追踪或遥测上报。应用设置、API 密钥和可选对话记忆保存在用户自己的 Mac 上，不属于开源仓库内容。

当用户主动选择云端功能时，完成请求所需的数据会发送给相应服务商：云端大模型接收对话文本，云端 TTS 接收需要朗读的文本，MiMo 混合识别接收当前轮次的音频。浮屿不会将原始录音作为长期记忆保存。

“允许说话打断”默认开启。开启后，浮屿会在自身朗读或 Hermes 执行期间检测用户是否开始说话。Apple 本地识别不上传音频；选择 MiMo 混合识别时，检测到并提交的当前轮音频会发送给 MiMo 做最终校正。用户可在高级设置中关闭打断功能。

Hermes / CUA 操作前确认默认开启。用户可以在高级设置中关闭，但这会允许模型规划的操作直接执行。

导入的 SillyTavern 角色卡与提示词预设在本机解析并保存为浮屿偏好，导入本身不会上传文件。使用云端模型聊天时，已启用的人格和提示词会作为对话上下文发送给用户选择的模型服务商。

## English

FuYu includes no advertising, user tracking, or telemetry. Settings, API credentials, and optional conversation memory remain on the user's Mac and are not part of the source repository.

When the user enables a cloud feature, only the data required for that request is sent to the selected provider: conversation text for cloud models, text for cloud TTS, and current-turn audio for MiMo hybrid recognition. FuYu does not retain raw recordings as long-term memory.

**Allow voice interruption** is enabled by default. While enabled, FuYu listens for the user to speak during its own reply or a running Hermes action. Apple on-device recognition does not upload audio; with MiMo hybrid recognition, the detected and submitted turn audio is sent to MiMo for final correction. Voice interruption can be disabled in Advanced Settings.

Approval before Hermes / CUA actions is enabled by default. Users may disable it in Advanced Settings, which allows model-planned actions to execute directly.

Imported SillyTavern character cards and prompt presets are parsed locally and stored as FuYu preferences; importing a file does not upload it. When a cloud model is used for chat, the enabled persona and prompt text are included in the context sent to the provider selected by the user.
