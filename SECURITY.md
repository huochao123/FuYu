# 安全政策 / Security Policy

## 报告问题 / Reporting a vulnerability

请不要在公开 Issue 中发布 API 密钥、个人配置、对话内容或可直接利用的安全细节。提交报告前请删除日志中的个人信息，并说明受影响版本、复现步骤和预期影响。

Do not post API keys, personal configuration, conversation content, or immediately exploitable details in a public issue. Remove personal information from logs and include the affected version, reproduction steps, and expected impact.

## 本地数据 / Local data

以下内容不得提交到仓库：`credentials.json`、`conversation-memory.json`、个人配置备份、签名证书和本机构建目录。项目的 `.gitignore` 已默认排除这些内容，但贡献者仍应在提交前自行检查。

The following must never be committed: `credentials.json`, `conversation-memory.json`, personal configuration backups, signing certificates, and local build directories. The project `.gitignore` excludes them by default, but contributors must still review every commit.
