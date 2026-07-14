# 隐私说明 / Privacy

## 中文

浮屿不包含广告、用户追踪或遥测上报。应用设置、API 密钥和可选对话记忆保存在用户自己的 Mac 上，不属于开源仓库内容。

当用户主动选择云端功能时，完成请求所需的数据会发送给相应服务商：云端大模型接收对话文本，云端 TTS 接收需要朗读的文本，MiMo 混合识别接收当前轮次的音频。浮屿不会将原始录音作为长期记忆保存。

Hermes / CUA 操作前确认默认开启。用户可以在高级设置中关闭，但这会允许模型规划的操作直接执行。

## English

FuYu includes no advertising, user tracking, or telemetry. Settings, API credentials, and optional conversation memory remain on the user's Mac and are not part of the source repository.

When the user enables a cloud feature, only the data required for that request is sent to the selected provider: conversation text for cloud models, text for cloud TTS, and current-turn audio for MiMo hybrid recognition. FuYu does not retain raw recordings as long-term memory.

Approval before Hermes / CUA actions is enabled by default. Users may disable it in Advanced Settings, which allows model-planned actions to execute directly.
