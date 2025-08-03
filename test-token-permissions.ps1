# 测试Token权限和API调用

Write-Host "=== 测试Token权限和API调用 ===" -ForegroundColor Magenta
Write-Host "==========================================" -ForegroundColor Magenta

# 测试Token权限
function Test-TokenPermissions {
    Write-Host "`n=== 测试Token权限 ===" -ForegroundColor Cyan
    
    try {
        # 检查gh认证状态
        $auth = gh auth status --json token,scopes
        if ($LASTEXITCODE -eq 0) {
            $authObj = $auth | ConvertFrom-Json
            Write-Host "✓ gh认证状态正常" -ForegroundColor Green
            Write-Host "Token范围: $($authObj.scopes -join ', ')" -ForegroundColor Gray
            
            # 检查是否有issues权限
            if ($authObj.scopes -contains "repo" -or $authObj.scopes -contains "issues") {
                Write-Host "✓ 有issues权限" -ForegroundColor Green
                return $true
            } else {
                Write-Host "✗ 缺少issues权限" -ForegroundColor Red
                return $false
            }
        } else {
            Write-Host "✗ gh认证失败" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "✗ 检查Token权限失败: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 测试Issue #1访问
function Test-Issue1Access {
    Write-Host "`n=== 测试Issue #1访问 ===" -ForegroundColor Cyan
    
    try {
        $issue = gh issue view 1 --json number,title,state
        if ($LASTEXITCODE -eq 0) {
            $issueObj = $issue | ConvertFrom-Json
            Write-Host "✓ Issue #1 访问成功" -ForegroundColor Green
            Write-Host "标题: $($issueObj.title)" -ForegroundColor Gray
            Write-Host "状态: $($issueObj.state)" -ForegroundColor Gray
            return $true
        } else {
            Write-Host "✗ Issue #1 访问失败" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "✗ 访问Issue #1失败: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 测试Issue更新
function Test-IssueUpdate {
    Write-Host "`n=== 测试Issue更新 ===" -ForegroundColor Cyan
    
    $testBody = "# Token权限测试`n`n**测试时间**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n**测试内容**: 验证Token是否有更新Issue的权限"
    
    try {
        Write-Host "正在测试更新Issue #1..." -ForegroundColor Yellow
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
        Write-Host "✗ Issue更新异常: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 测试API直接调用
function Test-APICall {
    Write-Host "`n=== 测试API直接调用 ===" -ForegroundColor Cyan
    
    try {
        # 获取仓库信息
        $repo = gh api repos/$env:GITHUB_REPOSITORY
        if ($LASTEXITCODE -eq 0) {
            $repoObj = $repo | ConvertFrom-Json
            Write-Host "✓ API调用成功" -ForegroundColor Green
            Write-Host "仓库: $($repoObj.full_name)" -ForegroundColor Gray
            Write-Host "权限: $($repoObj.permissions.issues)" -ForegroundColor Gray
            return $true
        } else {
            Write-Host "✗ API调用失败" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "✗ API调用异常: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 测试Issue API更新
function Test-IssueAPIUpdate {
    Write-Host "`n=== 测试Issue API更新 ===" -ForegroundColor Cyan
    
    $testBody = "# API更新测试`n`n**测试时间**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n**测试内容**: 使用API直接更新Issue"
    
    try {
        Write-Host "正在使用API更新Issue #1..." -ForegroundColor Yellow
        
        $jsonBody = @{
            body = $testBody
        } | ConvertTo-Json -Compress
        
        $result = gh api --method PATCH "repos/$env:GITHUB_REPOSITORY/issues/1" --input - 2>&1
        $jsonBody | gh api --method PATCH "repos/$env:GITHUB_REPOSITORY/issues/1" --input -
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ API更新成功" -ForegroundColor Green
            Write-Host $result -ForegroundColor Gray
            return $true
        } else {
            Write-Host "✗ API更新失败" -ForegroundColor Red
            Write-Host $result -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "✗ API更新异常: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 主函数
function Main-Test {
    $results = @{}
    
    $results["TokenPermissions"] = Test-TokenPermissions
    $results["Issue1Access"] = Test-Issue1Access
    $results["IssueUpdate"] = Test-IssueUpdate
    $results["APICall"] = Test-APICall
    $results["IssueAPIUpdate"] = Test-IssueAPIUpdate
    
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
    if (-not $results["TokenPermissions"]) {
        Write-Host "  - 检查GitHub Token权限设置" -ForegroundColor Yellow
        Write-Host "  - 确保Token有repo或issues权限" -ForegroundColor Yellow
    }
    if (-not $results["IssueUpdate"] -and $results["Issue1Access"]) {
        Write-Host "  - Token有读取权限但缺少写入权限" -ForegroundColor Yellow
    }
    if (-not $results["APICall"]) {
        Write-Host "  - API调用失败，检查网络连接和Token有效性" -ForegroundColor Yellow
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