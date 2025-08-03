# Custom RustDesk 构建工作流 - 各步骤流程图

## 整体工作流概览

```mermaid
graph TD
    A[触发事件] --> B{事件类型}
    B -->|workflow_dispatch| C[手动触发]
    B -->|issues| D[Issue触发]
    
    C --> E[trigger阶段]
    D --> E
    
    E --> F{参数验证}
    F -->|失败| G[结束]
    F -->|成功| H[review阶段]
    
    H --> I{需要审核?}
    I -->|否| J[直接通过]
    I -->|是| K[等待审核]
    
    J --> L[join-queue阶段]
    K --> L
    
    L --> M{加入队列成功?}
    M -->|失败| N[结束]
    M -->|成功| O[wait-build-lock阶段]
    
    O --> P{获取构建锁?}
    P -->|失败| Q[结束]
    P -->|成功| R[build阶段]
    
    R --> S{构建成功?}
    S -->|失败| T[finish阶段]
    S -->|成功| T
    
    T --> U[清理和通知]
```

## 1. Trigger阶段流程

```mermaid
graph TD
    A[开始trigger] --> B[加载trigger.sh]
    B --> C{事件类型判断}
    
    C -->|workflow_dispatch| D[提取workflow_dispatch参数]
    C -->|issues| E[提取issue参数]
    
    D --> F[应用默认值]
    E --> F
    
    F --> G[处理tag时间戳]
    G --> H[生成最终JSON数据]
    H --> I[验证参数]
    
    I --> J{验证结果}
    J -->|失败| K[设置validation_passed=false]
    J -->|成功| L[设置validation_passed=true]
    
    K --> M[输出到GitHub Actions]
    L --> M
    
    M --> N[结束trigger]
```

### Trigger阶段详细操作

```mermaid
graph TD
    A[trigger_manager调用] --> B{操作类型}
    
    B -->|extract-workflow-dispatch| C[从inputs提取参数]
    B -->|extract-issue| D[从issue body解析参数]
    B -->|apply-defaults| E[应用默认值配置]
    B -->|process-tag| F[添加时间戳到tag]
    B -->|generate-data| G[生成build_params结构]
    B -->|validate-parameters| H[验证必要参数]
    B -->|output-to-github| I[输出trigger_data]
    
    C --> J[返回参数变量]
    D --> J
    E --> J
    F --> J
    G --> J
    H --> K{验证结果}
    K -->|成功| L[返回0]
    K -->|失败| M[返回1]
    I --> N[设置输出变量]
```

## 2. Review阶段流程

```mermaid
graph TD
    A[开始review] --> B[加载review.sh]
    B --> C[获取trigger_data]
    C --> D[验证参数]
    
    D --> E{验证结果}
    E -->|失败| F[处理拒绝]
    E -->|成功| G[检查是否需要审核]
    
    F --> H[在issue中回复错误]
    H --> I[设置review_passed=false]
    
    G --> J{需要审核?}
    J -->|否| K[直接通过]
    J -->|是| L[在issue中回复需要审核]
    
    K --> M[设置review_passed=true]
    L --> N[处理审核流程]
    
    N --> O{审核结果}
    O -->|通过| P[设置review_passed=true]
    O -->|拒绝| Q[设置review_passed=false]
    O -->|超时| R[设置review_passed=false]
    
    M --> S[清理issue内容]
    P --> S
    Q --> T[结束review]
    R --> T
    
    S --> U[结束review]
```

### Review阶段详细操作

```mermaid
graph TD
    A[review_manager调用] --> B{操作类型}
    
    B -->|validate| C[验证服务器参数]
    B -->|need-review| D[检查是否需要审核]
    B -->|handle-review| E[处理审核流程]
    B -->|handle-rejection| F[处理拒绝情况]
    B -->|output-data| G[输出审核结果]
    
    C --> H{验证结果}
    H -->|成功| I[返回0]
    H -->|失败| J[返回错误信息]
    
    D --> K{审核条件}
    K -->|需要| L[返回true]
    K -->|不需要| M[返回false]
    
    E --> N[等待审核回复]
    N --> O{审核结果}
    O -->|approve| P[返回0]
    O -->|reject| Q[返回1]
    O -->|timeout| R[返回2]
    
    F --> S[生成拒绝通知]
    G --> T[设置输出变量]
```

## 3. Join-Queue阶段流程

```mermaid
graph TD
    A[开始join-queue] --> B[加载queue-manager.sh]
    B --> C[确定issue_number和build_id]
    C --> D[获取Issue锁]
    
    D --> E{获取Issue锁成功?}
    E -->|失败| F[结束join-queue]
    E -->|成功| G[获取队列锁]
    
    G --> H{获取队列锁成功?}
    H -->|失败| I[释放Issue锁]
    H -->|成功| J[读取队列数据]
    
    I --> F
    J --> K[检查队列长度]
    K --> L{队列是否已满?}
    
    L -->|是| M[释放所有锁]
    L -->|否| N[添加新项目到队列]
    
    M --> F
    N --> O{添加成功?}
    O -->|失败| P[释放所有锁]
    O -->|成功| Q[更新队列数据]
    
    P --> F
    Q --> R[释放队列锁和Issue锁]
    R --> S[返回队列位置]
    S --> T[设置join_success=true]
    T --> U[结束join-queue]
```

### Queue Manager详细操作

```mermaid
graph TD
    A[queue_manager调用] --> B{操作类型}
    
    B -->|join| C[加入队列流程]
    B -->|acquire| D[获取构建锁]
    B -->|data| E[获取队列数据]
    B -->|release-*| F[释放各种锁]
    
    C --> G[三锁获取流程]
    G --> H[Issue锁]
    H --> I[队列锁]
    I --> J[添加队列项]
    J --> K[释放锁]
    
    D --> L[等待构建锁可用]
    L --> M[获取构建锁]
    
    E --> N[从Issue#1读取数据]
    
    F --> O[释放指定锁]
```

## 4. Wait-Build-Lock阶段流程

```mermaid
graph TD
    A[开始wait-build-lock] --> B[加载queue-manager.sh]
    B --> C[确定issue_number和build_id]
    C --> D[获取构建锁]
    
    D --> E{获取构建锁成功?}
    E -->|失败| F[设置build_lock_acquired=false]
    E -->|成功| G[设置build_lock_acquired=true]
    
    F --> H[结束wait-build-lock]
    G --> H
```

## 5. Build阶段流程

```mermaid
graph TD
    A[开始build] --> B[加载build.sh]
    B --> C[提取构建数据]
    
    C --> D{提取成功?}
    D -->|失败| E[设置build_success=false]
    D -->|成功| F[处理构建数据]
    
    E --> G[输出错误信息]
    F --> H{处理成功?}
    
    H -->|失败| I[设置build_success=false]
    H -->|成功| J[执行构建过程]
    
    I --> G
    J --> K[模拟构建步骤]
    K --> L[生成下载URL]
    L --> M[设置build_success=true]
    
    G --> N[结束build]
    M --> N
```

### Build阶段详细操作

```mermaid
graph TD
    A[build_manager调用] --> B{操作类型}
    
    B -->|extract-data| C[从build_params提取参数]
    B -->|process-data| D[执行构建过程]
    B -->|output-data| E[输出构建结果]
    B -->|pause| F[暂停测试]
    
    C --> G[验证必要参数]
    G --> H[设置环境变量]
    
    D --> I[准备构建环境]
    I --> J[同步RustDesk代码]
    J --> K[应用定制参数]
    K --> L[编译RustDesk]
    L --> M[生成安装包]
    M --> N[记录构建时间]
    
    E --> O[生成下载URL]
    O --> P[设置输出变量]
```

## 6. Finish阶段流程

```mermaid
graph TD
    A[开始finish] --> B[加载finish.sh]
    B --> C[确定构建状态]
    C --> D[解析构建数据]
    D --> E[设置完成环境]
    
    E --> F[获取构建参数]
    F --> G{获取成功?}
    G -->|失败| H[使用备选参数]
    G -->|成功| I[使用获取的参数]
    
    H --> J[清理构建环境]
    I --> J
    
    J --> K{清理成功?}
    K -->|失败| L[设置cleanup_completed=false]
    K -->|成功| M[设置cleanup_completed=true]
    
    L --> N[释放三锁架构]
    M --> N
    
    N --> O{锁释放结果}
    O -->|部分失败| P[设置lock_released=partial]
    O -->|全部成功| Q[设置lock_released=success]
    O -->|全部失败| R[设置lock_released=failure]
    
    P --> S[输出完成数据]
    Q --> S
    R --> S
    
    S --> T[生成完成通知]
    T --> U[发送邮件通知]
    
    U --> V{发送成功?}
    V -->|失败| W[设置notification_sent=false]
    V -->|成功| X[设置notification_sent=true]
    
    W --> Y[结束finish]
    X --> Y
```

### Finish阶段详细操作

```mermaid
graph TD
    A[finish_manager调用] --> B{操作类型}
    
    B -->|setup-environment| C[设置完成环境]
    B -->|get-params| D[获取和解密参数]
    B -->|send-notification| E[发送邮件通知]
    B -->|cleanup| F[清理构建环境]
    B -->|release-triple-lock| G[释放三锁]
    B -->|output-data| H[输出完成数据]
    
    D --> I[从队列获取数据]
    I --> J[解密参数]
    
    G --> K[释放构建锁]
    K --> L[释放队列锁]
    L --> M[释放Issue锁]
    
    H --> N[验证完成状态]
    N --> O[设置输出变量]
```

## 数据流图

```mermaid
graph LR
    A[GitHub Event] --> B[trigger.sh]
    B --> C[trigger_data JSON]
    C --> D[review.sh]
    D --> E[queue-manager.sh]
    E --> F[build.sh]
    F --> G[finish.sh]
    
    C --> H[build_params]
    H --> I[tag, email, customer等]
    
    E --> J[队列数据]
    J --> K[Issue #1]
    
    F --> L[构建结果]
    L --> M[下载URL]
    
    G --> N[完成状态]
    N --> O[通知邮件]
```

## 锁管理流程

```mermaid
graph TD
    A[开始锁操作] --> B{操作类型}
    
    B -->|获取锁| C[检查锁状态]
    B -->|释放锁| D[直接释放]
    
    C --> E{锁是否可用?}
    E -->|是| F[设置锁持有者]
    E -->|否| G[等待或失败]
    
    F --> H[更新锁信息]
    H --> I[返回成功]
    
    G --> J[返回失败]
    D --> K[清除锁信息]
    K --> L[返回成功]
```

## 错误处理流程

```mermaid
graph TD
    A[发生错误] --> B{错误类型}
    
    B -->|参数验证失败| C[在issue中回复错误]
    B -->|队列已满| D[返回队列满错误]
    B -->|构建失败| E[记录错误信息]
    B -->|锁获取失败| F[重试或放弃]
    B -->|通知发送失败| G[记录但继续]
    
    C --> H[设置相应状态]
    D --> H
    E --> H
    F --> H
    G --> H
    
    H --> I[继续或结束流程]
```

## 关键决策点

```mermaid
graph TD
    A[触发事件] --> B{事件类型}
    B -->|workflow_dispatch| C[手动触发流程]
    B -->|issues| D[Issue触发流程]
    
    C --> E[参数验证]
    D --> E
    
    E --> F{验证结果}
    F -->|失败| G[结束]
    F -->|成功| H{需要审核?}
    
    H -->|否| I[直接进入队列]
    H -->|是| J[等待审核]
    
    J --> K{审核结果}
    K -->|通过| I
    K -->|拒绝| L[结束]
    K -->|超时| L
    
    I --> M{队列状态}
    M -->|已满| N[结束]
    M -->|有空位| O[加入队列]
    
    O --> P{获取构建锁}
    P -->|成功| Q[开始构建]
    P -->|失败| R[结束]
    
    Q --> S{构建结果}
    S -->|成功| T[完成处理]
    S -->|失败| T
    
    T --> U[清理和通知]
```

这些流程图展示了整个Custom RustDesk构建工作流的详细运作方式，包括每个阶段的决策点、错误处理和状态转换。 