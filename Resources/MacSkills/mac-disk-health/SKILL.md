---
name: mac-disk-health
description: Diagnose Mac disk health, SMART status, APFS file-system errors, I/O failures, Disk Utility First Aid, and external-drive disconnects.
---

# 磁盘与文件系统健康

1. 先确认卷宗、物理磁盘、APFS容器和故障是否来自内置或外置存储。
2. 读取SMART状态、I/O错误、异常断开和磁盘工具结果；可用空间不代表磁盘健康。
3. 文件系统错误与硬件介质故障分开判断，保留原始错误和时间。
4. 运行急救、抹盘或分区前先验证备份；禁止在唯一副本上冒险修复。
5. 外置盘同时检查线缆、供电、接口和休眠，不直接把断连归咎于磁盘。
6. 修复后重新挂载并验证读写与持续稳定性。
