# Handoff

## Current State
最新桌面反馈新增 3 个修正点：去掉用量区与未激活账号行的底部背景块；未激活账号用量文案从 `last` 改为 `left`；点击刷新时需要显示整体 loading 遮罩，数据返回后再取消。
本轮仍只做 UI 与刷新交互表现层，不改其他核心功能。
已完成实现并验证：去掉了用量卡片与未激活账号行的底色块，未激活账号用量文案改为 `left`，手动 `Refresh` 会显示整体 loading 遮罩，数据返回后关闭。
当前自动化回归为 `19` 个测试通过。

## Current Rules
- 只做 MVP
- 不增加不必要实体，不过度设计，不过度兜底
- 优先复用 `~/.codex/auth.json` 与 `~/.codex/accounts/registry.json`
- `5h / 周` 额度优先从 `~/.codex/sessions/*.jsonl` 的最新 `token_count.rate_limits` 读取
- 切换结果以新开的 Codex CLI 会话生效为准
- 本轮只做 UI 和文案，不改动其他核心功能

## Main Risks
- 刷新 loading 遮罩需要与初始加载、自动刷新区分开，避免误改现有刷新语义
- 未激活账号用量展示依赖 `registry.json.last_usage` 历史快照，部分账号可能仍然无数据

## Next Step
做一次桌面视觉确认，重点看底色块是否已消失、`left` 文案是否正确、刷新遮罩是否只在手动刷新时出现。
