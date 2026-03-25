# Plan

## Steps
1. 建立 macOS 菜单栏应用骨架
2. 实现本地账号与额度读取服务
3. 实现账号切换写入逻辑
4. 接入菜单栏 UI
5. 增加最小测试
6. 做手工验证

## Dependencies
- 本机已有 Codex CLI 本地认证
- 可读取 `~/.codex/` 下本地文件
- Xcode / Swift 工具链可用

## Risks
- 切换账号可能需要新开 CLI 会话才生效
- 额度读取依赖最新会话快照

## Rollback / Fallback
如切换能力在本地验证中不稳定，则先保留只读账号列表与额度展示，不扩展复杂恢复逻辑。
