# Handoff

## Current State
已明确需求：开发 `macOS 菜单栏应用`，管理 `Codex CLI 本地认证`，支持多账号切换，并显示每个账号的 `5h / 周` 剩余额度。
MVP 已完成首版实现，并通过主代理代码审查、自动化测试与人工验证。
首轮体验修正已完成：应用存活期间每 5 分钟自动刷新一次本地状态，`5h / 周` 重置时间已显示完整日期时间。
当前进入仓库收口：配置本仓库 git 身份，推送远端，并将误提交的 `.DS_Store` 与 `AGENTS.md` 从版本库中移除。

## Current Rules
- 只做 MVP
- 不增加不必要实体，不过度设计，不过度兜底
- 优先复用 `~/.codex/auth.json` 与 `~/.codex/accounts/registry.json`
- `5h / 周` 额度优先从 `~/.codex/sessions/*.jsonl` 的最新 `token_count.rate_limits` 读取
- 切换结果以新开的 Codex CLI 会话生效为准

## Main Risks
- 已运行的 Codex CLI 进程可能不会立即感知账号切换
- 本地会话限额快照可能滞后于刚切换的账号
- `auth.json` 与 `registry.json` 存在并发写风险，需要原子写入
- 菜单栏 UI 已编译通过，但本轮未做真实桌面点击验收

## Next Step
完成仓库清理与远端推送；如需继续，下一步补“新增登录账号”入口，并评估按账号缓存各自额度快照。
