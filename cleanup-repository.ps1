# 仓库清理脚本 (PowerShell版本)
# 使用gh调用99-delete_issues和99-delete_workflow_runs工作流

# 清理Issues
function Cleanup-Issues {
    Write-Host "开始清理Issues..." -ForegroundColor Green
    
    # 调用99-delete_issues工作流
    Write-Host "触发99-delete_issues工作流..." -ForegroundColor Yellow
    
    try {
        $result = gh workflow run "99-delete_issues.yml" --field mode="删除模式" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "99-delete_issues工作流触发成功" -ForegroundColor Green
            Write-Host $result
        }
        else {
            Write-Host "99-delete_issues工作流触发失败: $result" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "99-delete_issues工作流触发异常: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    
    return $true
}

# 清理Workflow Runs
function Cleanup-WorkflowRuns {
    Write-Host "开始清理Workflow Runs..." -ForegroundColor Green
    
    # 调用99-delete_workflow_runs工作流
    Write-Host "触发99-delete_workflow_runs工作流..." -ForegroundColor Yellow
    
    try {
        $result = gh workflow run "99-delete_workflow_runs.yml" --field mode="删除模式" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "99-delete_workflow_runs工作流触发成功" -ForegroundColor Green
            Write-Host $result
        }
        else {
            Write-Host "99-delete_workflow_runs工作流触发失败: $result" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "99-delete_workflow_runs工作流触发异常: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    
    return $true
}

# 主函数
function Main {
    
    # 执行清理操作
    Write-Host "开始仓库清理操作..." -ForegroundColor Cyan
    
    # 清理Issues
    if (-not (Cleanup-Issues)) {
        Write-Host "Issues清理失败" -ForegroundColor Red
        exit 1
    }
    
    # 清理Workflow Runs
    if (-not (Cleanup-WorkflowRuns)) {
        Write-Host "Workflow Runs清理失败" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "清理操作完成！" -ForegroundColor Green
    
    # 显示工作流状态
    Write-Host "查看工作流状态:" -ForegroundColor Cyan
    Write-Host "  gh run list --workflow=99-delete_issues.yml" -ForegroundColor Yellow
    Write-Host "  gh run list --workflow=99-delete_workflow_runs.yml" -ForegroundColor Yellow
}

# 错误处理
try {
    # 运行主函数
    Main
}
catch {
    Write-Host "脚本执行被中断: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} 