# Custom RustDesk — Agent 指南

## Health Stack

### 开发机（快速，不触发 CI）

- shell: `bash -n .github/workflows/scripts/*.sh`
- smoke: `bash scripts/health-check.sh`

### 编译机 2.18（完整回归）

- full: `bash run-tests.sh workflow-tests`
- optional: `bash run-tests.sh all`（含 gh 队列/触发类，需 `BUILD_TOKEN` 等环境）

### 不在范围

- Docker Hub `makepkg` 拉取偶发失败：接受上游行为，不做镜像插针
