# Handoff

## Current State
已完成当前账号用量的 API 优先刷新：`CodexDataStore` 现在会优先读取 `~/.codex/auth.json` 中的 `access_token` / `account_id` 请求 ChatGPT usage API；手动刷新和定时刷新都复用这条路径。
API 失败或返回空窗口时，会回退到现有本地 session / `registry.json.last_usage` 历史快照；未激活账号仍只显示缓存历史。
切换账号后新激活账号的用量刷新问题已修复：当前账号会优先使用与激活账号匹配的 `auth.json` 上下文，不匹配时才回退到该账号快照 auth。
本轮已补上“账号失效”透传：当 active account 的 usage API 返回 `401/403/404` 等无权限/上下文失效时，会保留旧 usage 作为历史，但把账号标记为 `Re-login required`，并在当前状态区显示 `Account access invalid. Re-login required.`。相关回归测试已通过 `24` 个测试。
已完成“从本地列表彻底删除账号”：删除会移除本地 snapshot、更新 `registry.json`；若删除当前激活账号，会自动切到剩余第一个账号并同步 `auth.json`，若已无剩余账号则清空当前 auth。UI 已补最小确认弹窗与删除入口。当前回归测试已通过 `28` 个测试。
最新反馈已处理：账号不可用判定已收紧为更稳的规则，`Switch account` / `Logout account` 也已改成更易识别的胶囊按钮样式。当前回归测试已通过 `29` 个测试。
新的桌面反馈说明问题还剩一层：未激活账号目前仍然主要展示历史缓存，只有“当前激活账号”才会触发失效校验，所以某些已失效的未激活账号仍会显示 `Has history`。

## Current Rules
- 只做 MVP
- 不增加不必要实体，不过度设计，不过度兜底
- 优先复用 `~/.codex/auth.json` 与 `~/.codex/accounts/registry.json`
- 当前激活账号用量优先通过 `https://chatgpt.com/backend-api/wham/usage` 获取
- API 失败时保留本地缓存回退显示
- `401/403/404` 视为账号访问失效，必须显式提示
- 当前优先补未激活账号的失效识别，不做无关扩展

## Main Risks
- API 方式会把 `access_token` 与 `account_id` 发到 `https://chatgpt.com/backend-api/wham/usage`
- 进度条长度与百分比语义必须一致，避免“数值对但视觉错”
- 还需要一次真实桌面确认，验证删除当前账号时的切换与列表刷新符合预期
- 未激活账号如果不做校验，仍会把失效账号伪装成“可切换的历史账号”

## Next Step
补未激活账号的失效识别，并验证列表展示。
