---
name: mac-kernel-panic
description: Diagnose unexpected Mac restarts, kernel panics, shutdown causes, hardware suspicion, and system-level failures.
---

# 意外重启与内核恐慌

1. 先确认发生时间、是否出现panic报告、关机原因码和最近硬件或系统变化。
2. 保留原始panic摘要、涉事扩展、进程与时间戳，不仅截取结论行。
3. 区分一次偶发、外设驱动、第三方系统扩展、系统缺陷与潜在硬件故障。
4. 不因报告出现某个进程名就断言它是根因；结合多次事件共同特征。
5. 先断开非必要外设并更新备份，再安排安全模式、诊断或服务支持。
6. 重复panic或数据风险应升级为用户介入，软件不能假装已经修好硬件。
