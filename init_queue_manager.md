# 队列管理Issue初始化

## 手动初始化Issue #1

如果队列管理出现问题，请手动创建或更新Issue #1，内容如下：

```markdown
## 构建队列管理

**最后更新时间：** 2024-01-15 10:00:00

### Issue队列 (最多3个)
- 当前数量：0/3

### Workflow队列 (最多5个)
- 当前数量：0/5

### 总队列 (最多5个)
- 当前数量：0/5

---

### 队列数据
```json
{"issue_queue":[],"workflow_queue":[]}
```
```

## 操作步骤

1. 在仓库中创建Issue #1（如果不存在）
2. 将上述内容复制到Issue body中
3. 保存Issue

## 注意事项

- Issue #1必须存在且包含正确的JSON格式数据
- 队列数据必须包含 `issue_queue` 和 `workflow_queue` 两个数组
- 初始状态两个数组都应该是空的 