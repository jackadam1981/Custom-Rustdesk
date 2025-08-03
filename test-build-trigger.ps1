# 统一构建触发测试脚本 (PowerShell版本)
# 整合所有测试功能，包含菜单选择

# 设置debug模式
$env:ACTIONS_STEP_DEBUG = "true"
$env:ACTIONS_RUNNER_DEBUG = "true"

Write-Host "=== 统一构建触发测试脚本 ===" -ForegroundColor Magenta
Write-Host "Debug模式已启用" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Magenta

# 显示菜单
function Show-Menu {
    Write-Host "`n选择测试类型:" -ForegroundColor Cyan
    Write-Host "1. workflow_dispatch 触发测试" -ForegroundColor White
    Write-Host "2. issues 触发测试" -ForegroundColor White
    Write-Host "3. 查看最新工作流运行" -ForegroundColor White
    Write-Host "4. 监控工作流运行状态" -ForegroundColor White
    Write-Host "5. 查看工作流日志" -ForegroundColor White
    Write-Host "6. 清理测试数据" -ForegroundColor White
    Write-Host "7. 完整模拟测试 (workflow_dispatch + issues)" -ForegroundColor White
    Write-Host "0. 退出" -ForegroundColor Red
    Write-Host ""
}

# workflow_dispatch触发测试
function Test-WorkflowDispatch {
    Write-Host "`n=== workflow_dispatch 触发测试 ===" -ForegroundColor Cyan
    
    $inputs = @{
        tag = "v1.2.3-test"
        email = "test@example.com"
        customer = "测试客户"
        customer_link = ""
        slogan = "测试版本"
        super_password = "test123"
        rendezvous_server = "192.168.1.100"
        rs_pub_key = ""
        api_server = "http://192.168.1.100:21114"
        enable_debug = "true"
    }
    
    Write-Host "触发参数:" -ForegroundColor Yellow
    foreach ($key in $inputs.Keys) {
        Write-Host "  $key`: $($inputs[$key])" -ForegroundColor Gray
    }
    
    try {
        Write-Host "`n正在触发 CustomBuildRustdesk 工作流..." -ForegroundColor Yellow
        
        $inputArgs = @()
        foreach ($key in $inputs.Keys) {
            $inputArgs += "--field", "$key=$($inputs[$key])"
        }
        
        $result = gh workflow run "CustomBuildRustdesk.yml" @inputArgs 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "? workflow_dispatch 触发成功" -ForegroundColor Green
            Write-Host $result -ForegroundColor Gray
            
            # 获取运行ID
            $runId = $result | Select-String -Pattern "Created workflow_dispatch event for .* at .*" | ForEach-Object {
                if ($_ -match "(\d+)") { $matches[1] }
            }
            
            if ($runId) {
                Write-Host "运行ID: $runId" -ForegroundColor Cyan
                return $runId
            }
        } else {
            Write-Host "? workflow_dispatch 触发失败" -ForegroundColor Red
            Write-Host $result -ForegroundColor Red
            return $null
        }
    }
    catch {
        Write-Host "? workflow_dispatch 触发异常: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# issues触发测试
function Test-IssuesTrigger {
    Write-Host "`n=== issues 触发测试 ===" -ForegroundColor Cyan
    
    $issueBody = @"
# 构建请求

**标签**: v1.2.4-issue-test
**邮箱**: issue-test@example.com
**客户**: 测试客户-issue
**服务器地址**: 192.168.1.200
**API服务器**: 192.168.1.200
**中继服务器**: 192.168.1.200
**密钥**: issue-test-key-456
**标语**: 测试版本-issue

请构建自定义RustDesk客户端。
"@
    
    Write-Host "Issue内容:" -ForegroundColor Yellow
    Write-Host $issueBody -ForegroundColor Gray
    
    try {
        Write-Host "`n正在创建测试Issue..." -ForegroundColor Yellow
        
        $result = gh issue create --title "[build] 测试构建" --body $issueBody 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "? Issue创建成功" -ForegroundColor Green
            Write-Host $result -ForegroundColor Gray
            
            # 提取Issue编号
            $issueNumber = $result | Select-String -Pattern "#(\d+)" | ForEach-Object {
                if ($_ -match "#(\d+)") { $matches[1] }
            }
            
            if ($issueNumber) {
                Write-Host "Issue编号: $issueNumber" -ForegroundColor Cyan
                return $issueNumber
            }
        } else {
            Write-Host "? Issue创建失败" -ForegroundColor Red
            Write-Host $result -ForegroundColor Red
            return $null
        }
    }
    catch {
        Write-Host "? Issue创建异常: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# 查看最新工作流运行
function View-LatestRuns {
    Write-Host "`n=== 查看最新工作流运行 ===" -ForegroundColor Cyan
    
    try {
        Write-Host "最近5个工作流运行:" -ForegroundColor Yellow
        gh run list --limit 5
    }
    catch {
        Write-Host "获取运行列表失败: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 监控工作流运行状态
function Monitor-WorkflowRun {
    param([string]$RunId)
    
    if (-not $RunId) {
        $RunId = Read-Host "请输入运行ID"
    }
    
    Write-Host "`n=== 监控工作流运行状态 ===" -ForegroundColor Cyan
    Write-Host "运行ID: $RunId" -ForegroundColor Yellow
    
    $maxAttempts = 30
    $attempt = 0
    
    while ($attempt -lt $maxAttempts) {
        $attempt++
        Write-Host "`n检查尝试 $attempt/$maxAttempts..." -ForegroundColor Gray
        
        try {
            $status = gh run view $RunId --json status,conclusion,createdAt,updatedAt,headBranch,event,workflowName
            
            if ($LASTEXITCODE -eq 0) {
                $statusObj = $status | ConvertFrom-Json
                Write-Host "状态: $($statusObj.status)" -ForegroundColor $(if ($statusObj.status -eq "completed") { "Green" } elseif ($statusObj.status -eq "in_progress") { "Yellow" } else { "Red" })
                Write-Host "结论: $($statusObj.conclusion)" -ForegroundColor $(if ($statusObj.conclusion -eq "success") { "Green" } elseif ($statusObj.conclusion -eq "failure") { "Red" } else { "Gray" })
                Write-Host "工作流: $($statusObj.workflowName)" -ForegroundColor Cyan
                Write-Host "事件: $($statusObj.event)" -ForegroundColor Cyan
                Write-Host "分支: $($statusObj.headBranch)" -ForegroundColor Cyan
                
                if ($statusObj.status -eq "completed") {
                    Write-Host "? 工作流运行完成" -ForegroundColor Green
                    return $statusObj
                }
            } else {
                Write-Host "获取运行状态失败" -ForegroundColor Red
            }
        }
        catch {
            Write-Host "监控异常: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host "等待30秒后重试..." -ForegroundColor Gray
        Start-Sleep -Seconds 30
    }
    
    Write-Host "监控超时" -ForegroundColor Red
    return $null
}

# 查看工作流日志
function View-WorkflowLogs {
    param([string]$RunId)
    
    if (-not $RunId) {
        $RunId = Read-Host "请输入运行ID"
    }
    
    Write-Host "`n=== 查看工作流日志 ===" -ForegroundColor Cyan
    Write-Host "运行ID: $RunId" -ForegroundColor Yellow
    
    try {
        Write-Host "正在获取日志..." -ForegroundColor Yellow
        gh run view $RunId --log
    }
    catch {
        Write-Host "获取日志失败: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 清理测试数据
function Cleanup-TestData {
    Write-Host "`n=== 清理测试数据 ===" -ForegroundColor Cyan
    
    try {
        Write-Host "正在列出最近的Issues..." -ForegroundColor Yellow
        gh issue list --limit 10
        
        $issueNumber = Read-Host "`n输入要关闭的Issue编号 (直接回车跳过)"
        if ($issueNumber) {
            Write-Host "正在关闭Issue #$issueNumber..." -ForegroundColor Yellow
            gh issue close $issueNumber --delete-branch
            Write-Host "? Issue已关闭" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "清理失败: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 完整模拟测试
function Complete-Simulation {
    Write-Host "`n=== 完整模拟测试 ===" -ForegroundColor Cyan
    Write-Host "将依次执行 workflow_dispatch 和 issues 触发测试" -ForegroundColor Yellow
    
    $results = @{}
    
    # 1. workflow_dispatch触发
    Write-Host "`n步骤1: workflow_dispatch 触发测试" -ForegroundColor Magenta
    $workflowRunId = Test-WorkflowDispatch
    $results["WorkflowDispatch"] = $workflowRunId -ne $null
    
    if ($workflowRunId) {
        Write-Host "`n是否监控此运行状态? (y/n)" -ForegroundColor Yellow
        $monitor = Read-Host
        if ($monitor -eq "y" -or $monitor -eq "Y") {
            Monitor-WorkflowRun $workflowRunId
        }
    }
    
    # 等待一段时间
    Write-Host "`n等待30秒后进行下一个测试..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30
    
    # 2. issues触发
    Write-Host "`n步骤2: issues 触发测试" -ForegroundColor Magenta
    $issueNumber = Test-IssuesTrigger
    $results["IssuesTrigger"] = $issueNumber -ne $null
    
    # 输出测试结果
    Write-Host "`n=== 测试结果摘要 ===" -ForegroundColor Magenta
    foreach ($test in $results.Keys) {
        $status = if ($results[$test]) { "? 成功" } else { "? 失败" }
        $color = if ($results[$test]) { "Green" } else { "Red" }
        Write-Host "  $test`: $status" -ForegroundColor $color
    }
    
    Write-Host "`n完整模拟测试完成！" -ForegroundColor Green
}

# 主循环
function Main-Loop {
    do {
        Show-Menu
        $choice = Read-Host "请输入选择 (0-7)"
        
        switch ($choice) {
            "1" { Test-WorkflowDispatch }
            "2" { Test-IssuesTrigger }
            "3" { View-LatestRuns }
            "4" { Monitor-WorkflowRun }
            "5" { View-WorkflowLogs }
            "6" { Cleanup-TestData }
            "7" { Complete-Simulation }
            "0" { 
                Write-Host "`n退出测试脚本" -ForegroundColor Green
                return 
            }
            default { 
                Write-Host "`n无效选择，请输入 0-7" -ForegroundColor Red
            }
        }
        
        if ($choice -ne "0") {
            Write-Host "`n按任意键继续..." -ForegroundColor Gray
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        
    } while ($choice -ne "0")
}

# 错误处理
try {
    Main-Loop
}
catch {
    Write-Host "`n测试过程中发生错误: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} 