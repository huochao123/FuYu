# 参与贡献 / Contributing

感谢你帮助改进浮屿。欢迎提交错误报告、交互建议、模型适配和代码改进。

Thank you for helping improve FuYu. Bug reports, interaction proposals, model integrations, and code contributions are welcome.

## 提交前 / Before submitting

1. 不要提交 API 密钥、个人配置、对话记忆或私人截图。
2. 保持界面文案以中文为主，并为面向用户的新功能补充清晰说明。
3. 对涉及 Mac 操作、权限和数据发送的改动说明安全影响。
4. 运行构建与自检：

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build
.build/debug/MiMoMac --self-test
```

1. Never commit API keys, personal configuration, conversation memory, or private screenshots.
2. Keep user-facing behavior clear and document new features.
3. Explain the security impact of changes involving Mac actions, permissions, or data transfer.
4. Run the build and self-test commands above before opening a pull request.
