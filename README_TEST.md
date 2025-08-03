# Custom Rustdesk 工作流测试工具

这个测试工具用于模拟和测试 Custom Rustdesk 构建工作流的各个阶段，使用 GitHub CLI (gh) 命令进行本地测试。

## 功能特性

### 🔧 工作流理解
- **触发处理**: 模拟从 issue 或手动触发中提取参数
- **审核验证**: 验证参数并处理审核流程  
- **队列管理**: 使用三锁架构管理构建队列
- **构建执行**: 执行实际的构建过程
- **完成处理**: 清理和通知

### 🚀 测试功能
- **真实数据模拟**: 生成唯一的测试数据，避免冲突
- **多种触发方式**: 支持 workflow_dispatch 和 issue 两种触发方式
- **实时监控**: 实时跟踪工作流运行状态和进度
- **日志分析**: 自动下载和分析工作流运行日志
- **结果分析**: 详细分析工作流运行结果和失败原因
- **资源清理**: 自动清理测试过程中创建的资源

## 前置要求

### 1. 安装依赖
```bash
# 安装 GitHub CLI
# Ubuntu/Debian
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install gh

# 安装 jq
sudo apt install jq
```

### 2. 配置 GitHub CLI
```bash
# 登录 GitHub CLI
gh auth login

# 验证登录状态
gh auth status
```

### 3. 确保权限
确保你的 GitHub 账户对目标仓库有以下权限：
- `issues: write` - 创建和管理 issues
- `actions: read` - 查看工作流运行
- `contents: read` - 读取仓库内容

## 使用方法

### 1. 运行测试脚本
```bash
# 给脚本执行权限
chmod +x test_workflow.sh

# 运行测试
./test_workflow.sh
```

### 2. 选择测试模式
脚本会提示你选择测试模式：

```
请选择触发方式:
1) workflow_dispatch (手动触发)
2) issue (创建issue触发)  
3) 两种方式都测试
请输入选择 (1/2/3):
```

- **选项1**: 使用 `gh workflow run` 命令直接触发工作流
- **选项2**: 创建测试 issue，让工作流自动触发
- **选项3**: 两种方式都测试，全面验证工作流

### 3. 监控测试过程
脚本会自动：
- 生成唯一的测试数据
- 触发工作流
- 实时监控运行状态
- 下载运行日志
- 分析运行结果
- 清理测试资源

## 测试数据说明

### 生成的测试参数
每次测试都会生成唯一的参数：

```json
{
  "tag": "test-build-1703123456",
  "customer": "测试客户-1703123456", 
  "email": "test-1703123456@example.com",
  "super_password": "testpass1703123456",
  "rendezvous_server": "192.168.1.100",
  "api_server": "http://192.168.1.100:21114",
  "slogan": "测试标语-1703123456",
  "customer_link": "https://example.com/test-1703123456",
  "rs_pub_key": "",
  "enable_debug": true
}
```

### Issue 内容格式
当选择 issue 触发时，会创建包含以下格式的 issue：

```markdown
## 构建参数

- **标签**: test-build-1703123456
- **客户**: 测试客户-1703123456
- **邮箱**: test-1703123456@example.com
- **标语**: 测试标语-1703123456
- **超级密码**: testpass1703123456
- **Rendezvous服务器**: 192.168.1.100
- **API服务器**: http://192.168.1.100:21114
- **客户链接**: https://example.com/test-1703123456
- **RS公钥**: 

## 构建请求

请为上述参数构建自定义Rustdesk版本。

构建ID: test-1703123456
```

## 输出说明

### 1. 实时状态监控
```
[INFO] 状态: in_progress, 结论: null
[INFO] 运行URL: https://github.com/user/repo/actions/runs/123456789
[INFO] 作业状态:
  - trigger: completed (success)
  - review: completed (success)  
  - join-queue: completed (success)
  - wait-build-lock: completed (success)
  - build: in_progress (running)
  - finish: queued (null)
```

### 2. 日志下载
```
[INFO] 下载工作流运行日志...
[SUCCESS] 日志已下载到目录: workflow_logs_123456789
[INFO] 日志文件列表:
  - workflow_logs_123456789/trigger/1_Checkout_code.txt
  - workflow_logs_123456789/trigger/2_Process_trigger_and_validate_parameters.txt
  - workflow_logs_123456789/review/1_Checkout_code.txt
  - workflow_logs_123456789/review/2_Review_and_validate.txt
```

### 3. 结果分析
```
[INFO] 运行详情:
  - 状态: completed
  - 结论: success
  - 运行URL: https://github.com/user/repo/actions/runs/123456789
[INFO] 作业结果分析:
  - trigger: completed (success)
  - review: completed (success)
  - join-queue: completed (success)
  - wait-build-lock: completed (success)
  - build: completed (success)
  - finish: completed (success)
[SUCCESS] 所有步骤都成功完成
```

## 故障排除

### 常见问题

#### 1. GitHub CLI 未登录
```
[ERROR] GitHub CLI 未登录
[INFO] 请运行: gh auth login
```
**解决方案**: 运行 `gh auth login` 并按照提示完成登录

#### 2. 权限不足
```
[ERROR] 工作流触发失败
```
**解决方案**: 检查 GitHub 账户对仓库的权限，确保有 `issues: write` 和 `actions: read` 权限

#### 3. 工作流未找到
```
[ERROR] 未找到目标工作流: CustomBuildRustdesk.yml
```
**解决方案**: 确保在正确的仓库中运行，且工作流文件存在

#### 4. 监控超时
```
[ERROR] 监控超时，工作流运行时间超过 1800 秒
```
**解决方案**: 检查工作流配置，可能需要调整超时时间或检查构建环境

### 调试技巧

#### 1. 启用详细日志
```bash
# 设置环境变量启用详细输出
export DEBUG=1
./test_workflow.sh
```

#### 2. 手动检查工作流
```bash
# 查看工作流列表
gh workflow list

# 查看特定工作流
gh workflow view .github/workflows/CustomBuildRustdesk.yml

# 查看运行历史
gh run list --workflow=CustomBuildRustdesk.yml
```

#### 3. 检查 Issue 状态
```bash
# 查看所有 issues
gh issue list

# 查看特定 issue
gh issue view <issue_number>
```

## 高级用法

### 1. 自定义测试数据
可以修改脚本中的 `generate_test_data()` 函数来生成自定义的测试数据。

### 2. 批量测试
可以创建脚本循环运行测试，进行压力测试：

```bash
#!/bin/bash
for i in {1..5}; do
    echo "运行第 $i 次测试..."
    ./test_workflow.sh
    sleep 60  # 等待1分钟再开始下次测试
done
```

### 3. 集成到 CI/CD
可以将测试脚本集成到 CI/CD 流程中，作为自动化测试的一部分。

## 注意事项

1. **资源清理**: 脚本会自动清理测试资源，但建议在测试完成后检查是否还有残留的 issues 或日志文件
2. **频率限制**: GitHub API 有频率限制，避免过于频繁的测试
3. **数据安全**: 测试数据包含敏感信息，确保在安全的环境中运行
4. **网络连接**: 确保网络连接稳定，特别是在下载日志时

## 贡献

欢迎提交 Issue 和 Pull Request 来改进这个测试工具！

## 许可证

本项目采用 MIT 许可证。 