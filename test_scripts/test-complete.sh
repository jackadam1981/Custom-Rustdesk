#!/bin/bash
# 完整端到端测试脚本 - 测试所有队列功能

# 加载测试框架
source test_scripts/test-framework.sh

# 测试脚本主函数
main() {
    # 初始化测试框架
    init_test_framework
    
    echo "========================================"
    echo "    完整端到端队列功能测试"
    echo "========================================"
    echo "此测试将验证所有队列功能的完整工作流程"
    echo ""
    
    # 步骤1: 重置队列状态
    log_step "步骤1: 重置队列状态"
    run_test "重置队列" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'reset'" \
        0
    
    # 步骤2: 测试队列加入
    log_step "步骤2: 测试队列加入功能"
    run_test "加入队列项目1" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' '{\"tag\":\"test-1\",\"email\":\"test1@example.com\",\"customer\":\"customer-1\",\"trigger_type\":\"workflow_dispatch\"}'" \
        0
    
    run_test "加入队列项目2" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' '{\"tag\":\"test-2\",\"email\":\"test2@example.com\",\"customer\":\"customer-2\",\"trigger_type\":\"workflow_dispatch\"}'" \
        0
    
    # 步骤3: 测试状态查询
    log_step "步骤3: 测试状态查询功能"
    run_test "查询队列状态" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'status'" \
        0
    
    run_test "查询构建锁状态" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'status'" \
        0
    
    # 步骤4: 测试构建锁获取
    log_step "步骤4: 测试构建锁获取功能"
    run_test "获取构建锁" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'acquire'" \
        0
    
    # 步骤5: 测试构建锁释放
    log_step "步骤5: 测试构建锁释放功能"
    run_test "释放构建锁" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'release'" \
        0
    
    # 步骤6: 测试队列离开
    log_step "步骤6: 测试队列离开功能"
    run_test "离开队列" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'leave'" \
        0
    
    # 步骤7: 测试清理功能
    log_step "步骤7: 测试清理功能"
    run_test "清理队列" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'cleanup'" \
        0
    
    # 步骤8: 最终重置
    log_step "步骤8: 最终重置"
    run_test "最终重置队列" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'reset'" \
        0
    
    # 清理测试框架
    cleanup_test_framework
}

# 运行主函数
main "$@"

