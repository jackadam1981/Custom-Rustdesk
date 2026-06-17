# Queue scripts — Issue 触发、审批、双锁队列

| 文件 | 职责 |
|------|------|
| `trigger.sh` | 解析 Issue / workflow_dispatch 参数 |
| `review.sh` | 审批与参数复核 |
| `queue-manager.sh` | 入队、双锁、限流 |
| `finish.sh` | 完成通知、出队、释放锁 |
| `issue-manager.sh` | GitHub Issue API |
| `issue-templates.sh` | 队列看板与通知 Markdown |
| `encryption-utils.sh` | 队列敏感字段加解密 |
| `debug-utils.sh` | 调试日志 |

队列数据持久化在 **Issue #1** 正文 JSON（`QUEUE_ISSUE_NUMBER`）。

Workflow 引用：`.github/workflows/scripts/queue/<name>.sh`
