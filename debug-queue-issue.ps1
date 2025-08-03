# 调试队列Issue问题脚本
# 检查Issue #1的状态和权限问题

Write-Host "=== 调试队列Issue问题 ===" -ForegroundColor Magenta
Write-Host "==========================================" -ForegroundColor Magenta

# 检查Issue #1是否存在
function Check-Issue1 {
    Write-Host "`n=== 检查Issue #1是否存在 ===" -ForegroundColor Cyan
    
    try {
        $issue = gh issue view 1 --json number,title,body,state,createdAt,updatedAt
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Issue #1 存在" -ForegroundColor Green
            $issueObj = $issue | ConvertFrom-Json
            Write-Host "标题: $($issueObj.title)" -ForegroundColor Gray
            Write-Host "状态: $($issueObj.state)" -ForegroundColor Gray
            Write-Host "创建时间: $($issueObj.createdAt)" -ForegroundColor Gray
            Write-Host "更新时间: $($issueObj.updatedAt)" -ForegroundColor Gray
            
            # 检查body内容
            if ($issueObj.body) {
                Write-Host "Body长度: $($issueObj.body.Length) 字符" -ForegroundColor Gray
                Write-Host "Body前100字符: $($issueObj.body.Substring(0, [Math]::Min(100, $issueObj.body.Length)))" -ForegroundColor Gray
            } else {
                Write-Host "Body为空" -ForegroundColor Yellow
            }
            
            return $true
        } else {
            Write-Host "✗ Issue #1 不存在" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "✗ 检查Issue失败: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 检查GitHub Token权限
function Check-TokenPermissions {
    Write-Host "`n=== 检查GitHub Token权限 ===" -ForegroundColor Cyan
    
    try {
        $auth = gh auth status --json token,scopes
        if ($LASTEXITCODE -eq 0) {
            $authObj = $auth | ConvertFrom-Json
            Write-Host "Token范围: $($authObj.scopes -join ', ')" -ForegroundColor Gray
            
            # 检查是否有issues权限
            if ($authObj.scopes -contains "repo") {
                Write-Host "✓ 有repo权限（包含issues权限）" -ForegroundColor Green
            } elseif ($authObj.scopes -contains "issues") {
                Write-Host "✓ 有issues权限" -ForegroundColor Green
            } else {
                Write-Host "✗ 缺少issues权限" -ForegroundColor Red
            }
            
            return $true
        } else {
            Write-Host "✗ 无法获取Token信息" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "✗ 检查Token失败: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 测试更新Issue
function Test-UpdateIssue {
    Write-Host "`n=== 测试更新Issue ===" -ForegroundColor Cyan
    
    $testBody = "# 队列管理测试

**测试时间**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
**测试内容**: 调试队列Issue更新问题

这是一个测试更新。"

    try {
        Write-Host "正在尝试更新Issue #1..." -ForegroundColor Yellow
        
        # 使用gh命令更新
        $result = gh issue edit 1 --body $testBody 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Issue更新成功" -ForegroundColor Green
            Write-Host $result -ForegroundColor Gray
            return $true
        } else {
            Write-Host "✗ Issue更新失败" -ForegroundColor Red
            Write-Host $result -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "✗ 更新Issue异常: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 检查API限制
function Check-APILimits {
    Write-Host "`n=== 检查API限制 ===" -ForegroundColor Cyan
    
    try {
        $limits = gh api rate_limit
        if ($LASTEXITCODE -eq 0) {
            $limitsObj = $limits | ConvertFrom-Json
            $core = $limitsObj.resources.core
            $search = $limitsObj.resources.search
            
            Write-Host "Core API限制:" -ForegroundColor Gray
            Write-Host "  剩余: $($core.remaining)/$($core.limit)" -ForegroundColor Gray
            Write-Host "  重置时间: $($core.reset)" -ForegroundColor Gray
            
            if ($core.remaining -lt 100) {
                Write-Host "⚠️ API调用次数较少，可能接近限制" -ForegroundColor Yellow
            } else {
                Write-Host "✓ API调用次数充足" -ForegroundColor Green
            }
            
            return $true
        } else {
            Write-Host "✗ 无法获取API限制信息" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "✗ 检查API限制失败: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 检查仓库权限
function Check-RepoPermissions {
    Write-Host "`n=== 检查仓库权限 ===" -ForegroundColor Cyan
    
    try {
        $repo = gh repo view --json permissions
        if ($LASTEXITCODE -eq 0) {
            $repoObj = $repo | ConvertFrom-Json
            $permissions = $repoObj.permissions
            
            Write-Host "仓库权限:" -ForegroundColor Gray
            Write-Host "  Issues: $($permissions.issues)" -ForegroundColor Gray
            Write-Host "  Contents: $($permissions.contents)" -ForegroundColor Gray
            Write-Host "  Actions: $($permissions.actions)" -ForegroundColor Gray
            
            if ($permissions.issues -eq "write") {
                Write-Host "✓ 有issues写入权限" -ForegroundColor Green
            } else {
                Write-Host "✗ 缺少issues写入权限" -ForegroundColor Red
            }
            
            return $true
        } else {
            Write-Host "✗ 无法获取仓库权限信息" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "✗ 检查仓库权限失败: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 主函数
function Main-Debug {
    $results = @{}
    
    $results["IssueExists"] = Check-Issue1
    $results["TokenPermissions"] = Check-TokenPermissions
    $results["RepoPermissions"] = Check-RepoPermissions
    $results["APILimits"] = Check-APILimits
    
    # 只有在Issue存在的情况下才测试更新
    if ($results["IssueExists"]) {
        $results["UpdateIssue"] = Test-UpdateIssue
    } else {
        $results["UpdateIssue"] = $false
    }
    
    # 输出结果摘要
    Write-Host "`n==========================================" -ForegroundColor Magenta
    Write-Host "调试结果摘要:" -ForegroundColor Magenta
    
    foreach ($test in $results.Keys) {
        $status = if ($results[$test]) { "✓ 正常" } else { "✗ 异常" }
        $color = if ($results[$test]) { "Green" } else { "Red" }
        Write-Host "  $test`: $status" -ForegroundColor $color
    }
    
    # 提供建议
    Write-Host "`n建议:" -ForegroundColor Cyan
    if (-not $results["IssueExists"]) {
        Write-Host "  - 创建Issue #1作为队列管理Issue" -ForegroundColor Yellow
    }
    if (-not $results["TokenPermissions"]) {
        Write-Host "  - 检查GitHub Token权限设置" -ForegroundColor Yellow
    }
    if (-not $results["RepoPermissions"]) {
        Write-Host "  - 检查仓库权限设置" -ForegroundColor Yellow
    }
    if (-not $results["UpdateIssue"]) {
        Write-Host "  - 检查Issue更新权限和API限制" -ForegroundColor Yellow
    }
}

# 运行调试
try {
    Main-Debug
}
catch {
    Write-Host "`n调试过程中发生错误: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} 