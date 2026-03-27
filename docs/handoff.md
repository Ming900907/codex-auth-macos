# Handoff

## Current State
已修复用量污染问题：`CodexDataStore` 现在会跳过本项目开发路径和子代理会话产生的污染 session 文件，继续回溯最近的有效额度快照。
已补回归测试并通过 `20` 个测试。

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
重新构建分发产物并确认打包后的用量回显正常。
