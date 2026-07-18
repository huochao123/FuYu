---
name: mac-network
description: Diagnose Mac Wi-Fi, Ethernet, USB adapters, VPN, physical link, DHCP, and DNS failures.
---

# 网络与外接网卡诊断

1. 按物理设备、接口链路、IP/DHCP、DNS、代理/VPN分层检查。
2. 设备被移除并重新枚举不是普通DNS故障。
3. 日志采集限定时间范围，保留接口名、设备事件和原始时间戳。
4. 先只读诊断；重置网络、卸载驱动或修改系统配置必须确认。
5. 修复后验证链路稳定性，而不只是一次ping成功。
