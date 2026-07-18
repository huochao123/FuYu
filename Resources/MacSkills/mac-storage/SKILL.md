---
name: mac-storage
description: Diagnose Mac storage usage, APFS snapshots, caches, purgeable space, large files, and safe cleanup.
---

# 存储与安全清理

1. 区分真实占用、可清除空间、APFS快照、缓存和可清除空间。
2. 扫描与执行分开；先显示项目、容量、收益和风险。
3. 仅对白名单缓存给出安全清理，默认移到废纸篓。
4. 不处理用户文档、照片图库、云盘占位文件和应用内部资源。
5. 执行后重新计算真实释放容量。

完成标准：结果可恢复、无越界路径、释放容量经过复查。
