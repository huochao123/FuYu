---
name: mac-sleep-wake
description: Diagnose Mac sleep, wake, lid-close drain, dark wakes, wake failures, and processes preventing idle sleep.
---

# 睡眠唤醒与待机

1. 确认是无法进入睡眠、频繁暗唤醒、合盖耗电还是无法唤醒。
2. 读取电源断言、唤醒原因、睡眠时间线和当时连接的外设。
3. 区分正常网络维护、备份、查找功能与异常进程阻止睡眠。
4. 不因单个wake reason直接定责，结合重复时间和设备变化。
5. 修改网络唤醒、Power Nap或外设设置前说明功能影响。
6. 用一段完整待机周期验证耗电和唤醒次数。
