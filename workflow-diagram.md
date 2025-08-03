# Custom Rustdesk Build Workflow - 三锁架构流程图

## 工作流概览

```mermaid
graph TD
    A[触发事件] --> B{触发类型}
    B -->|Issue触发| C[trigger job<br/>提取和验证参数]
    B -->|手动触发| C
    
    C --> D{参数验证}
    D -->|验证失败| E[finish job<br/>清理和通知]
    D -->|验证通过| F[review job<br/>审核验证]
    
    F --> G{需要审核?}
    G -->|不需要| H[审核通过]
    G -->|需要| I{审核结果}
    I -->|审核通过| H
    I -->|审核拒绝| E
    I -->|审核超时| E
    
    H --> J[join-queue job<br/>三锁队列管理]
    J --> K{加入队列}
    K -->|失败| E
    K -->|成功| L[wait-build-lock job<br/>等待构建锁]
    
    L --> M{获取构建锁}
    M -->|失败| E
    M -->|成功| N[build job<br/>执行构建]
    
    N --> O{构建结果}
    O -->|成功| P[finish job<br/>清理和通知]
    O -->|失败| P
    
    P --> Q[释放三锁]
    Q --> R[发送通知]
    R --> S[清理环境]
    S --> T[工作流结束]
    
    style A fill:#e1f5fe
    style C fill:#f3e5f5
    style F fill:#fff3e0
    style J fill:#e8f5e8
    style L fill:#e8f5e8
    style N fill:#e3f2fd
    style P fill:#fce4ec
    style Q fill:#fff8e1
```

## 三锁架构详细流程

```mermaid
graph TD
    subgraph "三锁架构"
        A1[Issue锁<br/>控制Issue内容访问] --> A2[获取Issue锁]
        A2 --> A3{Issue锁获取}
        A3 -->|失败| A4[重试或失败]
        A3 -->|成功| B1[队列锁<br/>控制队列操作]
        
        B1 --> B2[获取队列锁]
        B2 --> B3{队列锁获取}
        B3 -->|失败| B4[释放Issue锁]
        B3 -->|成功| C1[构建锁<br/>控制构建资源]
        
        C1 --> C2[获取构建锁]
        C2 --> C3{构建锁获取}
        C3 -->|失败| C4[释放队列锁]
        C4 --> C5[释放Issue锁]
        C3 -->|成功| D1[开始构建]
        
        D1 --> D2[构建完成]
        D2 --> D3[释放构建锁]
        D3 --> D4[释放队列锁]
        D4 --> D5[释放Issue锁]
    end
    
    style A1 fill:#ffcdd2
    style B1 fill:#f8bbd9
    style C1 fill:#c5cae9
    style D1 fill:#c8e6c9
```

## Job依赖关系图

```mermaid
graph TD
    subgraph "Job依赖链"
        A[trigger<br/>参数提取验证] --> B[review<br/>审核验证]
        B --> C[join-queue<br/>加入队列]
        C --> D[wait-build-lock<br/>获取构建锁]
        D --> E[build<br/>执行构建]
        A --> F[finish<br/>清理通知]
        B --> F
        C --> F
        D --> F
        E --> F
    end
    
    style A fill:#e3f2fd
    style B fill:#fff3e0
    style C fill:#e8f5e8
    style D fill:#e8f5e8
    style E fill:#f3e5f5
    style F fill:#fce4ec
```

## 条件执行逻辑

```mermaid
graph TD
    A[trigger job] --> A1{validation_passed}
    A1 -->|true| B[review job]
    A1 -->|false| F[finish job]
    
    B --> B1{review_passed}
    B1 -->|true| C[join-queue job]
    B1 -->|false| F
    
    C --> C1{join_success}
    C1 -->|true| D[wait-build-lock job]
    C1 -->|false| F
    
    D --> D1{build_lock_acquired}
    D1 -->|true| E[build job]
    D1 -->|false| F
    
    E --> E1{build_success}
    E1 -->|true| F
    E1 -->|false| F
    
    F --> G[释放三锁]
    G --> H[发送通知]
    H --> I[清理环境]
    
    style A fill:#e3f2fd
    style B fill:#fff3e0
    style C fill:#e8f5e8
    style D fill:#e8f5e8
    style E fill:#f3e5f5
    style F fill:#fce4ec
```

## 错误处理流程

```mermaid
graph TD
    A[工作流开始] --> B{检查点}
    B -->|参数验证失败| C[直接进入finish]
    B -->|审核失败| C
    B -->|加入队列失败| C
    B -->|获取锁失败| C
    B -->|构建失败| D[构建失败处理]
    
    C --> E[finish job]
    E --> F[释放已获取的锁]
    F --> G[发送失败通知]
    G --> H[清理环境]
    
    D --> I[记录错误信息]
    I --> E
    
    style A fill:#e1f5fe
    style C fill:#ffcdd2
    style D fill:#ffcdd2
    style E fill:#fce4ec
    style F fill:#fff8e1
    style G fill:#fff8e1
    style H fill:#fff8e1
```

## 关键特性说明

### 1. 三锁架构
- **Issue锁**: 控制对GitHub Issue内容的访问，防止并发更新
- **队列锁**: 控制对构建队列的操作，确保队列操作的原子性
- **构建锁**: 确保同一时间只有一个构建进程运行

### 2. 条件执行
- 每个job都有明确的前置条件
- 失败时立即跳转到finish job进行清理
- 使用`always()`确保finish job总是执行

### 3. 错误处理
- 每个步骤都有错误检查
- 失败时自动释放已获取的锁
- 发送适当的通知和错误信息

### 4. 资源管理
- 自动清理构建环境
- 释放所有获取的锁
- 发送构建结果通知

## 工作流状态转换

| 状态 | 触发条件 | 执行动作 | 下一状态 |
|------|----------|----------|----------|
| 参数验证 | 工作流触发 | 提取和验证参数 | 审核验证/失败处理 |
| 审核验证 | 参数验证通过 | 检查是否需要审核 | 队列管理/失败处理 |
| 队列管理 | 审核通过 | 获取三锁并加入队列 | 构建锁等待/失败处理 |
| 构建锁等待 | 成功加入队列 | 等待获取构建锁 | 构建执行/失败处理 |
| 构建执行 | 获取构建锁 | 执行构建过程 | 完成处理 |
| 完成处理 | 构建完成/失败 | 清理和通知 | 工作流结束 |

## 并发控制机制

```mermaid
graph LR
    A[并发请求] --> B[Issue锁]
    B --> C[队列锁]
    C --> D[构建锁]
    D --> E[串行执行]
    
    B1[其他请求] --> B2[等待Issue锁]
    B2 --> B3[等待队列锁]
    B3 --> B4[等待构建锁]
    
    style A fill:#e1f5fe
    style B fill:#ffcdd2
    style C fill:#f8bbd9
    style D fill:#c5cae9
    style E fill:#c8e6c9
    style B1 fill:#ffcdd2
    style B2 fill:#ffcdd2
    style B3 fill:#f8bbd9
    style B4 fill:#c5cae9
```

这个三锁架构确保了：
1. **数据一致性**: Issue锁防止并发更新
2. **队列安全**: 队列锁确保队列操作的原子性
3. **资源独占**: 构建锁确保构建资源的独占使用
4. **错误恢复**: 自动释放锁和清理资源 