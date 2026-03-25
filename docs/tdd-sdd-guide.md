# TDD / SDD Guide

本文件定义项目级的 TDD / SDD 落地方式。

## 1. 适用范围

- 非简单任务：先做 SDD，再做实现。
- 非简单代码变更：默认做 TDD。
- 纯文档、纯重命名、纯机械修改：可简化，但应明确说明原因。

## 2. 推荐流程

1. 写 `spec.md`
2. 审查 spec
3. 写 `plan.md`
4. 写 `tests.md`
5. 先让测试失败
6. 做最小实现
7. 让测试通过
8. 重构
9. 更新 `acceptance.md`
10. 更新相关索引与 `docs/handoff.md`

## 3. 文件建议

建议按任务建立目录，例如：

```text
docs/specs/<task-name>/
  spec.md
  plan.md
  tests.md
  acceptance.md
```

如果任务很小，也可以只保留 `spec.md` 和 `tests.md`，但应明确说明简化原因。

## 4. spec.md 模板

```md
# Spec

## Goal

## Scope

## Non-goals

## Inputs / Outputs

## Edge Cases

## Constraints

## Approach

## Risks

## Acceptance
```

## 5. plan.md 模板

```md
# Plan

## Steps

## Dependencies

## Risks

## Rollback / Fallback
```

## 6. tests.md 模板

```md
# Tests

## Normal Cases

## Error Cases

## Edge Cases

## Regression Cases

## Validation Method
```

## 7. acceptance.md 模板

```md
# Acceptance

## Done Criteria

## Validation Evidence

## Open Items
```

## 8. 执行约定

- `SDD` 关注做什么、为什么这样做、如何验收。
- `TDD` 关注如何证明行为正确。
- bug 修复优先补回归测试。
- 不要只靠打包结果证明实现正确。
- 如果实现偏离 spec，先更新 spec 或重新规划，再继续实现。

## 9. 工具建议

- 可选使用 Spec-Kit 之类工具生成 spec、plan、task。
- 工具只是辅助，不替代 `AGENTS.md` 中的门禁规则。
