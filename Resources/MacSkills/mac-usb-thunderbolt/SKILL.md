---
name: mac-usb-thunderbolt
description: Diagnose USB and Thunderbolt peripherals, docks, power delivery, device re-enumeration, bandwidth, and repeated disconnects.
---

# USB与雷雳外设

1. 记录设备型号、端口、线缆、扩展坞、供电和断开时间。
2. 区分物理设备被移除重枚举、驱动接口重建和上层网络或存储故障。
3. 检查总线速率、供电需求、共享带宽与系统日志中的attach/detach证据。
4. 交叉测试直连、另一端口、另一线缆和独立供电，每次只改变一个变量。
5. 存储设备断开先保护数据；网卡断开不要误诊为DNS。
6. 保留时间范围明确的原始日志用于保修或厂商支持。
