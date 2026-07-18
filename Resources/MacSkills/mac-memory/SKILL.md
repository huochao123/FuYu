---
name: mac-memory
description: Diagnose Mac memory pressure, swap use, compressed memory, memory leaks, and out-of-memory symptoms.
---

# 内存压力与交换

1. 优先读取内存压力而非只看“已用内存”，macOS会主动使用空闲内存作缓存。
2. 同时检查交换空间、压缩内存、进程增长趋势和系统卡顿时间。
3. 区分正常缓存、短时峰值、应用泄漏与内存容量不足。
4. 结束应用前提醒保存工作；系统进程不可仅因占用高就强退。
5. 重启只作为暂时恢复手段，不能替代泄漏来源诊断。
6. 处理后复查内存压力和交换增长是否停止。
