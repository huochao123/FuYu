---
name: mac-app-security
description: Diagnose Gatekeeper, notarization, XProtect, quarantine, unknown developers, suspicious apps, and Mac application trust.
---

# 应用安全与公证

1. 读取应用签名、开发者、公证、来源、隔离属性和系统拦截原文。
2. “无法验证开发者”“应用已损坏”和恶意软件告警是不同问题，不可混为一谈。
3. 优先核对官方来源和签名；未知名称不等于恶意，已签名也不保证绝对安全。
4. 不指导全局关闭Gatekeeper、SIP或XProtect，不静默移除安全属性。
5. 需要绕过单个可信应用时，必须由用户在系统界面明确确认并理解来源风险。
6. 可疑文件保留哈希和路径，建议隔离而非立即销毁证据。
