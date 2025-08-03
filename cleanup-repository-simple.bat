@echo off
chcp 65001 >nul

echo Starting repository cleanup...

REM Check if gh command is available
gh --version >nul 2>&1
if errorlevel 1 (
    echo Error: gh command not found. Please install GitHub CLI and login.
    echo Install GitHub CLI: https://cli.github.com/
    pause
    exit /b 1
)

REM Cleanup Issues
echo Cleaning up Issues...
echo Triggering 99-delete_issues workflow...

gh workflow run "99-delete_issues.yml" --field mode="删除模式"
if errorlevel 1 (
    echo 99-delete_issues workflow trigger failed
    pause
    exit /b 1
) else (
    echo 99-delete_issues workflow triggered successfully
)

REM Cleanup Workflow Runs
echo Cleaning up Workflow Runs...
echo Triggering 99-delete_workflow_runs workflow...

gh workflow run "99-delete_workflow_runs.yml" --field mode="删除模式"
if errorlevel 1 (
    echo 99-delete_workflow_runs workflow trigger failed
    pause
    exit /b 1
) else (
    echo 99-delete_workflow_runs workflow triggered successfully
)

echo Cleanup operation completed!

echo.
echo To check workflow status, run:
echo   gh run list --workflow=99-delete_issues.yml
echo   gh run list --workflow=99-delete_workflow_runs.yml
echo.

pause 