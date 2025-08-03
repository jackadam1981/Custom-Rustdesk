#!/bin/bash
# 仓库清理脚本
# 使用gh调用99-delete_issues和99-delete_workflow_runs工作流

# 清理Issues
cleanup_issues() {
  echo "开始清理Issues..."

  # 调用99-delete_issues工作流
  echo "触发99-delete_issues工作流..."

  local result=$(gh workflow run "99-delete_issues.yml" \
    --field mode="删除模式" \
    2>&1)

  if [ $? -eq 0 ]; then
    echo "99-delete_issues工作流触发成功"
    echo "$result"
  else
    echo "99-delete_issues工作流触发失败: $result"
    return 1
  fi
}

# 清理Workflow Runs
cleanup_workflow_runs() {
  echo "开始清理Workflow Runs..."

  # 调用99-delete_workflow_runs工作流
  echo "触发99-delete_workflow_runs工作流..."

  local result=$(gh workflow run "99-delete_workflow_runs.yml" \
    --field mode="删除模式" \
    2>&1)

  if [ $? -eq 0 ]; then
    echo "99-delete_workflow_runs工作流触发成功"
    echo "$result"
  else
    echo "99-delete_workflow_runs工作流触发失败: $result"
    return 1
  fi
}

# 主函数
main() {

  # 执行清理操作
  echo "开始仓库清理操作..."

  # 清理Issues
  if ! cleanup_issues; then
    echo "Issues清理失败"
    exit 1
  fi

  # 清理Workflow Runs
  if ! cleanup_workflow_runs; then
    echo "Workflow Runs清理失败"
    exit 1
  fi

  echo "清理操作完成！"

  # 显示工作流状态
  echo "查看工作流状态:"
  echo "  gh run list --workflow=99-delete_issues.yml"
  echo "  gh run list --workflow=99-delete_workflow_runs.yml"
}

# 错误处理
trap 'echo "脚本执行被中断"; exit 1' INT TERM

# 运行主函数
main "$@"
