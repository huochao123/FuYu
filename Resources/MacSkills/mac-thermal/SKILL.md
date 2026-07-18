---
name: mac-thermal
description: Diagnose Mac heat, sustained CPU load, memory pressure, battery drain, fan activity, and performance stalls.
---

# 性能与发热诊断

1. 读取持续CPU、内存压力、系统负载、运行时长和进程身份；不要用单次峰值定性。
2. 区分用户应用、系统索引、更新任务和失控进程。
3. 给出来源、连续采样证据、影响和可信度。
4. 只读检查可直接运行；结束进程前要求用户保存工作并确认。
5. 操作后重新采样，只有负载真实下降才能宣布改善。

完成标准：指出具体进程或明确说明证据不足；不得把瞬时升高称为持续异常。
