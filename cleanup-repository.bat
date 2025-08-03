@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

REM 仓库清理脚本 (批处理版本)
REM 使用gh调用99-delete_issues和99-delete_workflow_runs工作流

echo 开始仓库清理操作...

REM 检查gh命令是否可用
gh --version >nul 2>&1
if errorlevel 1 (
    echo 错误: 未找到gh命令。请确保已安装GitHub CLI并已登录。
    echo 安装GitHub CLI: https://cli.github.com/
    pause
    exit /b 1
)

REM 清理Issues
echo 开始清理Issues...
echo 触发99-delete_issues工作流...

gh workflow run "99-delete_issues.yml" --field mode="删除模式"
if errorlevel 1 (
    echo 99-delete_issues工作流触发失败
    pause
    exit /b 1
) else (
    echo 99-delete_issues工作流触发成功
)

REM 清理Workflow Runs
echo 开始清理Workflow Runs...
echo 触发99-delete_workflow_runs工作流...

gh workflow run "99-delete_workflow_runs.yml" --field mode="删除模式"
if errorlevel 1 (
    echo 99-delete_workflow_runs工作流触发失败
    pause
    exit /b 1
) else (
    echo 99-delete_workflow_runs工作流触发成功
)

echo 清理操作完成！

REM 显示工作流状态
echo.
echo 查看工作流状态:
echo   gh run list --workflow=99-delete_issues.yml
echo   gh run list --workflow=99-delete_workflow_runs.yml
echo.

pause 