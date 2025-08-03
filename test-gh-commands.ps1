# GitHub CLI 测试脚本 (PowerShell版本)
# 测试各种gh命令功能

# 测试gh命令是否可用
function Test-GHCommand {
    Write-Host "=== 测试gh命令可用性 ===" -ForegroundColor Cyan
    
    try {
        $version = gh --version
        Write-Host "? GitHub CLI 已安装" -ForegroundColor Green
        Write-Host $version -ForegroundColor Gray
        return $true
    }
    catch {
        Write-Host "? GitHub CLI 未安装或不可用" -ForegroundColor Red
        Write-Host "请安装: https://cli.github.com/" -ForegroundColor Yellow
        return $false
    }
}

# 测试gh认证状态
function Test-GHAuth {
    Write-Host "`n=== 测试gh认证状态 ===" -ForegroundColor Cyan
    
    try {
        $auth = gh auth status
        Write-Host "? GitHub CLI 已认证" -ForegroundColor Green
        Write-Host $auth -ForegroundColor Gray
        return $true
    }
    catch {
        Write-Host "? GitHub CLI 未认证" -ForegroundColor Red
        Write-Host "请运行: gh auth login" -ForegroundColor Yellow
        return $false
    }
}

# 测试仓库信息
function Test-RepoInfo {
    Write-Host "`n=== 测试仓库信息 ===" -ForegroundColor Cyan
    
    try {
        $repo = gh repo view --json name,description,url,defaultBranchRef
        Write-Host "? 成功获取仓库信息" -ForegroundColor Green
        Write-Host $repo -ForegroundColor Gray
        return $true
    }
    catch {
        Write-Host "? 获取仓库信息失败" -ForegroundColor Red
        return $false
    }
}

# 测试工作流列表
function Test-Workflows {
    Write-Host "`n=== 测试工作流列表 ===" -ForegroundColor Cyan
    
    try {
        $workflows = gh workflow list
        Write-Host "? 成功获取工作流列表" -ForegroundColor Green
        Write-Host $workflows -ForegroundColor Gray
        return $true
    }
    catch {
        Write-Host "? 获取工作流列表失败" -ForegroundColor Red
        return $false
    }
}

# 测试Issues列表
function Test-Issues {
    Write-Host "`n=== 测试Issues列表 ===" -ForegroundColor Cyan
    
    try {
        $issues = gh issue list --limit 5
        Write-Host "? 成功获取Issues列表" -ForegroundColor Green
        Write-Host $issues -ForegroundColor Gray
        return $true
    }
    catch {
        Write-Host "? 获取Issues列表失败" -ForegroundColor Red
        return $false
    }
}

# 测试工作流运行历史
function Test-WorkflowRuns {
    Write-Host "`n=== 测试工作流运行历史 ===" -ForegroundColor Cyan
    
    try {
        $runs = gh run list --limit 5
        Write-Host "? 成功获取工作流运行历史" -ForegroundColor Green
        Write-Host $runs -ForegroundColor Gray
        return $true
    }
    catch {
        Write-Host "? 获取工作流运行历史失败" -ForegroundColor Red
        return $false
    }
}

# 测试特定工作流
function Test-SpecificWorkflow {
    param([string]$WorkflowName)
    
    Write-Host "`n=== 测试特定工作流: $WorkflowName ===" -ForegroundColor Cyan
    
    try {
        $workflow = gh workflow view "$WorkflowName.yml" --json name,state,path
        Write-Host "? 成功获取工作流信息" -ForegroundColor Green
        Write-Host $workflow -ForegroundColor Gray
        return $true
    }
    catch {
        Write-Host "? 获取工作流信息失败" -ForegroundColor Red
        return $false
    }
}

# 测试工作流触发（不实际执行）
function Test-WorkflowTrigger {
    param([string]$WorkflowName)
    
    Write-Host "`n=== 测试工作流触发: $WorkflowName ===" -ForegroundColor Cyan
    
    try {
        # 只检查工作流是否存在，不实际触发
        $workflow = gh workflow view "$WorkflowName.yml" --json name
        Write-Host "? 工作流 $WorkflowName 存在，可以触发" -ForegroundColor Green
        Write-Host "要实际触发，请运行: gh workflow run '$WorkflowName.yml'" -ForegroundColor Yellow
        return $true
    }
    catch {
        Write-Host "? 工作流 $WorkflowName 不存在或无法访问" -ForegroundColor Red
        return $false
    }
}

# 测试仓库状态
function Test-RepoStatus {
    Write-Host "`n=== 测试仓库状态 ===" -ForegroundColor Cyan
    
    try {
        $status = gh repo sync
        Write-Host "? 仓库同步成功" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "? 仓库同步失败" -ForegroundColor Red
        return $false
    }
}

# 主测试函数
function Main-Test {
    Write-Host "开始GitHub CLI功能测试..." -ForegroundColor Magenta
    Write-Host "==========================================" -ForegroundColor Magenta
    
    $results = @{}
    
    # 基础测试
    $results["GHCommand"] = Test-GHCommand
    if (-not $results["GHCommand"]) {
        Write-Host "`n基础测试失败，停止后续测试" -ForegroundColor Red
        return
    }
    
    $results["GHAuth"] = Test-GHAuth
    if (-not $results["GHAuth"]) {
        Write-Host "`n认证测试失败，部分功能可能不可用" -ForegroundColor Yellow
    }
    
    # 功能测试
    $results["RepoInfo"] = Test-RepoInfo
    $results["Workflows"] = Test-Workflows
    $results["Issues"] = Test-Issues
    $results["WorkflowRuns"] = Test-WorkflowRuns
    
    # 测试特定工作流
    $results["CustomBuildRustdesk"] = Test-SpecificWorkflow "CustomBuildRustdesk"
    $results["DeleteIssues"] = Test-WorkflowTrigger "99-delete_issues"
    $results["DeleteWorkflowRuns"] = Test-WorkflowTrigger "99-delete_workflow_runs"
    
    # 仓库状态测试
    $results["RepoStatus"] = Test-RepoStatus
    
    # 输出测试结果摘要
    Write-Host "`n==========================================" -ForegroundColor Magenta
    Write-Host "测试结果摘要:" -ForegroundColor Magenta
    
    foreach ($test in $results.Keys) {
        $status = if ($results[$test]) { "? 通过" } else { "? 失败" }
        $color = if ($results[$test]) { "Green" } else { "Red" }
        Write-Host "  $test`: $status" -ForegroundColor $color
    }
    
    # 统计结果
    $passed = ($results.Values | Where-Object { $_ -eq $true }).Count
    $total = $results.Count
    $percentage = [math]::Round(($passed / $total) * 100, 1)
    
    Write-Host "`n总体结果: $passed/$total 测试通过 ($percentage%)" -ForegroundColor $(if ($percentage -ge 80) { "Green" } elseif ($percentage -ge 60) { "Yellow" } else { "Red" })
    
    # 提供建议
    Write-Host "`n建议:" -ForegroundColor Cyan
    if ($results["GHAuth"] -eq $false) {
        Write-Host "  - 运行 'gh auth login' 进行认证" -ForegroundColor Yellow
    }
    if ($results["CustomBuildRustdesk"] -eq $false) {
        Write-Host "  - 检查 CustomBuildRustdesk.yml 工作流是否存在" -ForegroundColor Yellow
    }
    if ($results["DeleteIssues"] -eq $false -or $results["DeleteWorkflowRuns"] -eq $false) {
        Write-Host "  - 检查清理工作流文件是否存在" -ForegroundColor Yellow
    }
}

# 错误处理
try {
    Main-Test
}
catch {
    Write-Host "`n测试过程中发生错误: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} 