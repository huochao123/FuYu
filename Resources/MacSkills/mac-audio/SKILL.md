---
name: mac-audio
description: Diagnose CoreAudio, microphones, output routes, speech recognition, echo, ducking, Bluetooth audio, and Fn voice activation.
---

# 音频与语音诊断

1. 分开检查输入设备、输出设备、权限、CoreAudio缓冲和识别回调。
2. 连续语音必须逐轮验证真实音频缓冲与最终文字，不能只看动画状态。
3. 使用回声消除区分用户说话与Mac自身播放声音。
4. 音量ducking结束后恢复原值；用户主动调高时不得覆盖。
5. 第二轮失败时重建识别会话，并保留录音交给混合识别兜底。

完成标准：至少连续两轮有真实输入证据；说明故障位于收音、识别还是提交环节。
