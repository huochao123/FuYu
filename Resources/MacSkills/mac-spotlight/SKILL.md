---
name: mac-spotlight
description: Diagnose Spotlight search omissions, mds and mdworker load, metadata indexing, exclusions, and safe reindexing.
---

# Spotlight与索引

1. 先确认搜索范围、文件真实存在、隐私排除和文件类型是否可索引。
2. 读取索引状态与mds/mdworker持续时间；系统更新后的短时高负载通常正常。
3. 区分索引正在构建、索引损坏、权限问题和云端占位文件。
4. 重建索引会产生明显CPU、磁盘与耗电负载，执行前需说明并确认。
5. 不删除未知metadata目录作为第一步。
6. 重建后用明确文件名和内容搜索验证结果。
