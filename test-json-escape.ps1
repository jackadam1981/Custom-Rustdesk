# 测试JSON转义功能

Write-Host "=== 测试JSON转义功能 ===" -ForegroundColor Magenta
Write-Host "==========================================" -ForegroundColor Magenta

# 测试JSON数据转义
function Test-JsonEscape {
    Write-Host "`n=== 测试JSON数据转义 ===" -ForegroundColor Cyan
    
    # 模拟队列数据
    $queueData = @{
        queue = @(
            @{
                build_id = "16699914424"
                build_title = "Custom Rustdesk Build"
                tag = "v1.2.3-test-20250803-015309"
                email = "test@example.com"
                customer = "测试客户"
                customer_link = ""
                super_password = "test123"
                slogan = "测试版本"
                rendezvous_server = "192.168.1.100"
                rs_pub_key = ""
                api_server = "http://192.168.1.100:21114"
                trigger_type = "workflow_dispatch"
                join_time = "2025-08-03 01:53:21"
            }
        )
        issue_locked_by = $null
        queue_locked_by = $null
        build_locked_by = $null
        issue_lock_version = 1
        queue_lock_version = 1
        build_lock_version = 1
        version = 3
    } | ConvertTo-Json -Depth 10
    
    Write-Host "原始JSON数据:" -ForegroundColor Gray
    Write-Host $queueData -ForegroundColor White
    
    # 模拟生成Issue body
    $currentTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $issueLockVersion = 1
    $issueLockedBy = "16699914424"
    $queueLockedBy = "无"
    $buildLockedBy = "无"
    
    $body = @"
## Issue 锁管理

**最后更新时间：** $currentTime

### Issue 锁状态
- **Issue 锁状态：** 占用 🔒
- **Issue 锁持有者：** $issueLockedBy
- **版本：** $issueLockVersion

### 标识信息
- **Run ID：** 16699914424
- **Issue ID：** 未获取

### 当前锁状态概览
- **队列锁：** $queueLockedBy
- **构建锁：** $buildLockedBy

---

### Issue 锁数据
```json
$queueData
```
"@
    
    Write-Host "`n生成的Issue body:" -ForegroundColor Gray
    Write-Host $body -ForegroundColor White
    
    # 测试转义
    $escapedBody = $body -replace '\\', '\\\\' -replace '"', '\"' -replace "`n", '\n' -replace "`r", '\r' -replace "`t", '\t'
    
    Write-Host "`n转义后的body:" -ForegroundColor Gray
    Write-Host $escapedBody -ForegroundColor White
    
    # 测试JSON格式
    $jsonPayload = @{
        body = $escapedBody
    } | ConvertTo-Json -Compress
    
    Write-Host "`n最终的JSON payload:" -ForegroundColor Gray
    Write-Host $jsonPayload -ForegroundColor White
    
    # 验证JSON格式是否正确
    try {
        $testObj = $jsonPayload | ConvertFrom-Json
        Write-Host "`n✓ JSON格式验证成功" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "`n✗ JSON格式验证失败: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 测试实际API调用
function Test-ActualAPIUpdate {
    Write-Host "`n=== 测试实际API调用 ===" -ForegroundColor Cyan
    
    $testBody = "# JSON转义测试`n`n**测试时间**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n**测试内容**: 验证JSON转义是否正常工作`n`n这是一个包含特殊字符的测试：`n- 换行符`n- 引号: 测试引号`n- 反斜杠: 测试反斜杠"
    
    try {
        Write-Host "正在测试更新Issue #1..." -ForegroundColor Yellow
        
        # 使用gh命令更新（gh会自动处理转义）
        $result = gh issue edit 1 --body $testBody 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ gh命令更新成功" -ForegroundColor Green
            Write-Host $result -ForegroundColor Gray
            return $true
        } else {
            Write-Host "✗ gh命令更新失败" -ForegroundColor Red
            Write-Host $result -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "✗ 更新异常: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 主函数
function Main-Test {
    $results = @{}
    
    $results["JsonEscape"] = Test-JsonEscape
    $results["ActualAPIUpdate"] = Test-ActualAPIUpdate
    
    # 输出结果摘要
    Write-Host "`n==========================================" -ForegroundColor Magenta
    Write-Host "测试结果摘要:" -ForegroundColor Magenta
    
    foreach ($test in $results.Keys) {
        $status = if ($results[$test]) { "✓ 成功" } else { "✗ 失败" }
        $color = if ($results[$test]) { "Green" } else { "Red" }
        Write-Host "  $test`: $status" -ForegroundColor $color
    }
    
    # 提供建议
    Write-Host "`n建议:" -ForegroundColor Cyan
    if (-not $results["JsonEscape"]) {
        Write-Host "  - JSON转义有问题，需要检查转义逻辑" -ForegroundColor Yellow
    }
    if (-not $results["ActualAPIUpdate"]) {
        Write-Host "  - API调用失败，可能是权限或网络问题" -ForegroundColor Yellow
    }
}

# 运行测试
try {
    Main-Test
}
catch {
    Write-Host "`n测试过程中发生错误: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} 