# Spec

## Goal
实现一个 `macOS 菜单栏应用`，支持 `Codex CLI 本地认证` 的多账号切换，并显示当前账号 `5h / 周` 剩余额度。

## Scope
- 菜单栏入口
- 本地账号列表
- 当前账号标识
- 账号切换
- 当前账号 `5h / 周` 剩余额度展示
- 手动刷新
- 按账号回显最近一次本地额度快照

## Non-goals
- 账号云同步
- 历史统计
- 自动切号
- 多平台支持
- 复杂设置页
- 跨账号推断实时额度

## Inputs / Outputs
- 输入：本地 Codex 账号信息、当前认证态、本机会话额度快照
- 输出：菜单栏状态、账号切换结果、额度展示、错误提示

## Constraints
- 只做 MVP
- 不引入新后端
- 不依赖打包验证
- 已运行中的 Codex CLI 会话不保证立即生效

## Edge Cases
- 账号数量为 0 或 1
- 额度快照不存在
- 当前账号与目标账号相同
- `auth.json` 或 `registry.json` 缺失
- 目标账号只有历史额度快照、没有最新会话

## Approach
- 用 SwiftUI `MenuBarExtra` 搭建菜单栏 App
- 读取 `~/.codex/accounts/registry.json` 与 `*.auth.json` 展示账号列表
- 切换时原子写入 `~/.codex/auth.json` 和 `registry.json`
- 从最新 `sessions/*.jsonl` 中解析 `token_count.rate_limits`
- 刷新时把当前激活账号对应的额度快照写回本地账号记录，切号后优先展示该账号最近一次快照

## Risks
- 本地数据结构不稳定
- 切换流程依赖 Codex CLI 内部行为
- 限额快照可能滞后
- `registry.json` 的扩展字段可能随 CLI 版本演进而变化

## Acceptance
- 能列出本地账号
- 能识别当前账号
- 能切换当前账号
- 能显示 `5h / 周` 剩余额度
- 数据缺失时有可理解的空态提示
