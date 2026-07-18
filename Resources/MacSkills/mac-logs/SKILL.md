---
name: mac-logs
description: Collect and interpret bounded macOS unified logs, crash reports, diagnostic evidence, timestamps, and support-ready records.
---

# 系统日志与诊断证据

1. 先确定故障发生的准确时间、进程、设备或接口，再限定日志范围。
2. 优先保存原始时间戳、进程名、事件文本和上下文，不只复制解释。
3. 避免无界限重复扫描统一日志，以免产生高负载和无关噪声。
4. 区分观察事实、合理推断和尚未证实的根因。
5. 输出给支持或保修时保留原文件、校验值和采集条件，并移除无关隐私。
6. 日志显示成功不替代真实功能复测。
