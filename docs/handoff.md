# Handoff

## Current State
按账号关联额度快照已完成：刷新时会把当前激活账号的最新本地额度写回 `registry.json`，切号后若目标账号暂无新会话，也会优先展示该账号最近一次缓存额度。
现状保持不变：MVP、登录新账号、登录取消与残留进程修复均已完成并验证通过。
本轮已修复登录完成后的 UI 状态回收：刷新账号列表成功或失败后，不再把“登录完成，正在刷新账号列表”长期留在界面上。
新的手工验证结果表明：刚登录的新账号稍后已经出现在本地 `registry.json`，但菜单栏 UI 在登录完成后的那次刷新里没有显示出来。
本轮已修复登录成功后的列表刷新时序：登录成功后会在短时间内有限次重试读取账号列表，直到检测到账号集合变化或达到上限。
本轮已确认真实根因：当前本机 `registry.json` 里的 `last_usage` 使用了原生结构（如 `resets_at` / `window_minutes`），而菜单栏应用仍按旧的 `remaining_percent` / `reset_at` 结构强解，导致读取账号时直接失败并显示 `The data couldn’t be read because it is missing.`。
已把 `CodexDataStore` 的额度快照解码改为兼容两种结构，并补充回归测试覆盖当前本机的 `registry.json` 形态。
当前自动化回归为 `17` 个测试通过。

## Current Rules
- 只做 MVP
- 不增加不必要实体，不过度设计，不过度兜底
- 优先复用 `~/.codex/auth.json` 与 `~/.codex/accounts/registry.json`
- `5h / 周` 额度优先从 `~/.codex/sessions/*.jsonl` 的最新 `token_count.rate_limits` 读取
- 切换结果以新开的 Codex CLI 会话生效为准

## Main Risks
- `codex login` 退出成功与 `registry.json` / `accounts/*.auth.json` 完成落盘之间仍可能存在延迟，需继续通过真实桌面流程确认没有新的时序问题
- 若 Codex CLI 后续改变本地账号落盘时机或文件结构，登录后重试策略可能需要再调
- 已运行的 Codex CLI 进程可能不会立即感知账号切换
- `auth.json` 与 `registry.json` 存在并发写风险，需要原子写入

## Next Step
做真实桌面复测，重点确认登录后不会再因 `last_usage` 结构变化报错，且新账号会正常显示在菜单栏列表中。
