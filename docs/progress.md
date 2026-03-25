# Progress

## Current Phase
MVP 首版已实现并完成人工验收。

## Done
- 明确产品目标为 `macOS 菜单栏应用`
- 确认切换对象为 `Codex CLI 本地认证`
- 确认 MVP 只做本地账号切换与 `5h / 周` 剩余额度展示
- 验证本地认证源为 `~/.codex/auth.json` 与 `~/.codex/accounts/registry.json`
- 验证额度可从 `~/.codex/sessions/*.jsonl` 的 `token_count.rate_limits` 读取
- 完成 SwiftUI 菜单栏应用骨架
- 完成本地账号切换、额度读取、手动刷新
- 完成最小单元测试并通过 `5` 个测试
- 完成每 5 分钟自动刷新与完整日期时间展示
- 完成真实桌面人工验证

## In Progress
- 无

## Next
- 评估“新增登录账号”入口
- 评估按账号关联额度快照

## Notes
当前优先级是做出稳定可用的 MVP，不扩展复杂设置和自动化策略。
