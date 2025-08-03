@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo GitHub CLI 测试脚本 (批处理版本)
echo ==========================================

REM 测试gh命令是否可用
echo === 测试gh命令可用性 ===
gh --version >nul 2>&1
if errorlevel 1 (
    echo ✗ GitHub CLI 未安装或不可用
    echo 请安装: https://cli.github.com/
    pause
    exit /b 1
) else (
    echo ✓ GitHub CLI 已安装
    gh --version
)

REM 测试gh认证状态
echo.
echo === 测试gh认证状态 ===
gh auth status >nul 2>&1
if errorlevel 1 (
    echo ✗ GitHub CLI 未认证
    echo 请运行: gh auth login
) else (
    echo ✓ GitHub CLI 已认证
    gh auth status
)

REM 测试仓库信息
echo.
echo === 测试仓库信息 ===
gh repo view --json name,description,url,defaultBranchRef >nul 2>&1
if errorlevel 1 (
    echo ✗ 获取仓库信息失败
) else (
    echo ✓ 成功获取仓库信息
    gh repo view --json name,description,url,defaultBranchRef
)

REM 测试工作流列表
echo.
echo === 测试工作流列表 ===
gh workflow list >nul 2>&1
if errorlevel 1 (
    echo ✗ 获取工作流列表失败
) else (
    echo ✓ 成功获取工作流列表
    gh workflow list
)

REM 测试Issues列表
echo.
echo === 测试Issues列表 ===
gh issue list --limit 5 >nul 2>&1
if errorlevel 1 (
    echo ✗ 获取Issues列表失败
) else (
    echo ✓ 成功获取Issues列表
    gh issue list --limit 5
)

REM 测试工作流运行历史
echo.
echo === 测试工作流运行历史 ===
gh run list --limit 5 >nul 2>&1
if errorlevel 1 (
    echo ✗ 获取工作流运行历史失败
) else (
    echo ✓ 成功获取工作流运行历史
    gh run list --limit 5
)

REM 测试特定工作流
echo.
echo === 测试CustomBuildRustdesk工作流 ===
gh workflow view "CustomBuildRustdesk.yml" --json name,state,path >nul 2>&1
if errorlevel 1 (
    echo ✗ CustomBuildRustdesk工作流不存在或无法访问
) else (
    echo ✓ CustomBuildRustdesk工作流存在
    gh workflow view "CustomBuildRustdesk.yml" --json name,state,path
)

REM 测试清理工作流
echo.
echo === 测试清理工作流 ===
gh workflow view "99-delete_issues.yml" --json name >nul 2>&1
if errorlevel 1 (
    echo ✗ 99-delete_issues工作流不存在
) else (
    echo ✓ 99-delete_issues工作流存在
)

gh workflow view "99-delete_workflow_runs.yml" --json name >nul 2>&1
if errorlevel 1 (
    echo ✗ 99-delete_workflow_runs工作流不存在
) else (
    echo ✓ 99-delete_workflow_runs工作流存在
)

REM 测试仓库同步
echo.
echo === 测试仓库同步 ===
gh repo sync >nul 2>&1
if errorlevel 1 (
    echo ✗ 仓库同步失败
) else (
    echo ✓ 仓库同步成功
)

echo.
echo ==========================================
echo 测试完成！
echo.
echo 常用gh命令参考:
echo   gh workflow list                    - 列出所有工作流
echo   gh workflow run "工作流名.yml"       - 触发工作流
echo   gh run list                        - 查看运行历史
echo   gh issue list                      - 查看Issues
echo   gh repo view                       - 查看仓库信息
echo   gh auth status                     - 查看认证状态
echo.
pause 