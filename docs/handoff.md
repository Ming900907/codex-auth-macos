# Handoff

## Current State
MVP 与本轮 UI/交互收口已完成，桌面确认通过：去掉了多余底色块，未激活账号用量文案改为 `left`，手动 `Refresh` 会显示整体 loading 遮罩并在返回后关闭。
当前自动化回归为 `19` 个测试通过，进入首个版本发布准备，计划打 `v0.1.0` 标签。

## Current Rules
- 只做 MVP
- 不增加不必要实体，不过度设计，不过度兜底
- 优先复用 `~/.codex/auth.json` 与 `~/.codex/accounts/registry.json`
- `5h / 周` 额度优先从 `~/.codex/sessions/*.jsonl` 的最新 `token_count.rate_limits` 读取
- 切换结果以新开的 Codex CLI 会话生效为准
- 本轮只做 UI 和文案，不改动其他核心功能

## Main Risks
- 未激活账号用量展示依赖 `registry.json.last_usage` 历史快照，部分账号可能仍然无数据

## Next Step
创建并推送 `v0.1.0` 标签，整理首个版本发布说明。
