# Codex Auth macOS Bar

`Codex Auth macOS Bar` 是一个面向 `Codex CLI` 本地认证环境的 `macOS` 菜单栏工具，用来管理本机多账号、切换当前账号，并显示当前账号的用量状态。

## What It Does

- 在菜单栏列出本地 Codex 账号
- 标记当前激活账号
- 切换当前账号
- 显示当前账号 `5h / weekly` 剩余额度
- 为未激活账号保留最近一次历史用量
- 手动刷新当前账号用量
- 支持登录新账号
- 支持从本地列表删除账号
- 对失效账号显示 `Re-login required`

## Requirements

- macOS `14+`
- 已安装并可使用 `Codex CLI`
- 本机存在 `~/.codex/auth.json` 和 `~/.codex/accounts/registry.json`
- 当前账号使用 ChatGPT/Codex 本地认证上下文，而不是单纯 API Key 模式

## Install

从 Release 下载最新 zip：

- Release: `https://github.com/Ming900907/codex-auth-macos/releases/tag/v0.1.1`
- Asset: `https://github.com/Ming900907/codex-auth-macos/releases/download/v0.1.1/CodexAuthMacOSBar.app.zip`

解压后得到 `CodexAuthMacOSBar.app`，直接运行即可。

如果被 Gatekeeper 拦截，可在 Finder 中右键应用并选择 `Open` 一次。

## Build From Source

```bash
swift build -c release
```

运行测试：

```bash
swift test --disable-sandbox
```

## How It Works

应用主要读取这些本地文件：

- `~/.codex/auth.json`
- `~/.codex/accounts/registry.json`
- `~/.codex/accounts/*.auth.json`
- `~/.codex/sessions/**/*.jsonl`

当前激活账号的实时用量优先通过 ChatGPT usage API 获取：

- `https://chatgpt.com/backend-api/wham/usage`

请求使用：

- `Authorization: Bearer <access_token>`
- `ChatGPT-Account-Id: <account_id>`

如果实时请求失败，界面会回退到本地历史快照显示。

## Account Status

- 当前账号会优先使用匹配激活账号的 `auth.json` 上下文取实时用量
- 未激活账号在展开详情时会做一次轻量校验
- 返回 `4xx`（除 `429` 外）或命中失效关键词时，会显示 `Re-login required`
- 失效账号仍可能保留旧用量历史，但不代表该账号当前仍可用

## Local Removal

`Logout account` 会从本地列表删除该账号：

- 删除对应 `*.auth.json` 快照
- 更新 `registry.json`
- 如果删除的是当前激活账号，会自动切到剩余第一个账号
- 如果已经没有剩余账号，会清空当前 `auth.json`

## Known Behaviors

- 已经运行中的 Codex CLI 会话不保证立即切到新账号
- 未激活账号的状态校验发生在你展开该账号详情时，不是后台持续轮询
- 历史用量是本地缓存，不代表该账号此刻一定可用
