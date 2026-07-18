---
name: mac-time-machine
description: Diagnose Time Machine freshness, destination availability, backup failures, exclusions, snapshots, and file restoration.
---

# Time Machine备份

1. 读取最后成功备份时间、目标位置、当前阶段和失败原因。
2. 区分本地APFS快照与可在磁盘损坏后恢复的外部备份。
3. 检查目标容量、网络可达性、排除项、加密状态和备份盘健康。
4. “正在备份”不等于可恢复；抽查关键文件和恢复入口。
5. 删除旧备份、重建目标或关闭加密前必须由用户确认。
6. 把备份过旧视为风险并明确告诉用户需要做什么。
