# Custom RustDesk — Agent 指南

## Health Stack

### 开发机（快速，不触发 CI）

- shell: `bash -n .github/workflows/scripts/*.sh`
- smoke: `bash scripts/health-check.sh`

### 编译机 2.18（完整回归）

- fixture: `bash run-tests.sh workflow-tests`
- **patch-lab: `bash run-tests.sh patch-lab`**（干净 clone 上游 → 插针 → 验证；**触发 CI 前必跑**）
- optional: `bash run-tests.sh all`（含 gh 队列/触发类，需 `BUILD_TOKEN` 等环境）

详见 [docs/patch-lab.md](docs/patch-lab.md)。分步 CI 实验验证（M0–M6）：[docs/experiment-verification.md](docs/experiment-verification.md)。

### 不在范围

- Docker Hub `makepkg` 拉取偶发失败：接受上游行为，不做镜像插针
