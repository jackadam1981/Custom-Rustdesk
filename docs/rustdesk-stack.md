# RustDesk 自建栈（集合文档）

> Custom RustDesk 客户端 + 2.22 自建服务端的全景说明。  
> **Outline（Wiki）：** [RustDesk 自建栈（2.22 服务端）](https://wiki.jackadam.top/doc/rustdesk-222-nxus8Lz4rs)  
> **部署策略：** 内网保留 **18444** 仅作管理后台（登录、用户/活动管理）；**不建议使用 Web Client**。远控用桌面客户端（21116/21117）。详见 §5.4。  
> 配置模板：`scripts/rustdesk-docker-compose-bridge.yaml`、`scripts/rustdesk-nginx-default.conf`  
> 客户端验收见 [experiment-verification.md](./experiment-verification.md)；CI/插针见 [verification-rollout.md](./verification-rollout.md)。

---

## 1. 架构总览

```
                    2.1 路由器
              DNS A→192.168.2.22  /  端口转发
                        │
    ┌───────────────────▼───────────────────────────────────────┐
    │  192.168.2.22  /storage/build/rustdesk/                   │
    │                                                           │
    │   rustdesk-int (Docker bridge)                            │
    │   ┌─────────┐ ┌─────────┐ ┌──────────────┐ ┌──────────┐ │
    │   │  hbbs   │ │  hbbr   │ │ rustdesk-api │ │  nginx   │ │
    │   │ 21116…  │ │ 21117   │ │    21114     │ │ 18444    │ │
    │   │ (内21118)│ │(内21119)│ │              │ │21118/21119│ │
    │   └────┬────┘ └────┬────┘ └──────┬───────┘ └────┬─────┘ │
    │        └───────────┴─────────────┴──────────────┘       │
    │                         ▲ ports 发布到宿主机               │
    └─────────────────────────┼─────────────────────────────────┘
                              │
         ┌────────────────────┼────────────────────┐
         │                    │                    │
   Windows 桌面客户端    （不推荐 Web Client）   外网 RustDesk
   (百信 preset exe)                         桌面客户端
   21116/21117          内网 18444→/_admin/     21116/21117
```

| 组件 | 镜像/版本 | 作用 |
|------|-----------|------|
| **hbbs** | `ghcr.io/rustdesk/rustdesk-server:1.1.15-armv7` | ID / rendezvous；UDP+TCP 21116 |
| **hbbr** | 同上 | 中继 21117；内建 WebSocket 21119 |
| **rustdesk-api** | `lejianwen/rustdesk-api` | 管理后台、PC API |
| **nginx** | `nginx:latest` | 内网 HTTPS **18444**（管理后台）；21118/21119 仅 Web Client 需要（**不建议启用**） |

---

## 2. 部署位置与域名

| 项 | 值 |
|----|-----|
| 主机 | `192.168.2.22`（`onecloud.jackadam.top`） |
| 目录 | `/storage/build/rustdesk/` |
| 域名 | `rustdesk.jackadam.top` |
| 内网 DNS（2.1） | A → `192.168.2.22`；AAAA → 公网 `::22`（见 §6） |

### 入口 URL

| 用途 | URL | 说明 |
|------|-----|------|
| **管理后台**（推荐内网） | `https://rustdesk.jackadam.top:18444/_admin/` | 登录、在线设备/终端、活动管理 |
| **API** | `http://rustdesk.jackadam.top:21114` | 查在线终端/脚本；**2.1 保留 WAN 转发**（明文 HTTP，见 §5.4） |
| Web Client | `https://rustdesk.jackadam.top:18444/webclient/` | **不建议使用**（§5.4） |

---

## 3. Docker：推荐 bridge，不用 host

### 3.1 原因（IPv6）

`network_mode: host` 时 hbbs 监听 `*:21116`，出站 IPv6 由内核选源地址。  
当 ddns 公布 `::22` 且 `use_tempaddr=2` 启用临时地址时：

```
host（失败）  客户端 → ::22:21116 ；回包源 = 临时 IPv6  → register_pk / key not confirmed
bridge（通过）  docker-proxy 保持回包与目的地址对称
```

内网把客户端四项钉 `192.168.2.22` 可绕过，但 **域名 + IPv6** 在 host 下不稳定。

### 3.2 网络模式

- **hbbs / hbbr**：`networks: rustdesk-int` + `ports`（见 §4）
- **hbbs `-r`**：仍用公网域名 `${RELAY_SERVER}:${RELAY_PORT}`，**不要**写成 `hbbr:21117`（给客户端下发中继地址）
- **21118 / 21119**：**不**映射在 hbbs/hbbr 宿主机上，只由 **nginx** 对外提供 TLS（§5）

### 3.3 部署

```bash
cd /storage/build/rustdesk
cp -a docker-compose.yaml docker-compose.yaml.bak-$(date -u +%Y%m%d-%H%M%S)
# 从仓库拷贝 scripts/rustdesk-docker-compose-bridge.yaml → docker-compose.yaml
# 从仓库拷贝 scripts/rustdesk-nginx-default.conf → conf.d/default.conf
docker compose up -d
```

验证：

```bash
docker inspect rustdesk-hbbs rustdesk-hbbr --format '{{.Name}} {{.HostConfig.NetworkMode}}'
# 期望 rustdesk-int

docker logs --tail 5 rustdesk-hbbs   # Listening on tcp/udp :21116
docker logs --tail 5 rustdesk-hbbr   # Listening on websocket :21119
```

---

## 4. 端口与转发

### 4.1 谁监听什么

| 端口 | 协议 | 宿主机监听者 | 容器内目标 | 用途 |
|------|------|--------------|------------|------|
| 21115 | TCP | hbbs (docker-proxy) | hbbs | NAT 探测 |
| 21116 | TCP+UDP | hbbs | hbbs | **ID / 注册（桌面客户端关键）** |
| 21117 | TCP+UDP | hbbr | hbbr | 中继 |
| 21114 | TCP | api（宿主机） | api | API / 在线终端（与 18444 同后端）；**2.1 保留转发** |
| **18444** | TCP | nginx | api:21114 | **内网 HTTPS 管理后台**（`/_admin/`） |
| ~~21118~~ | — | **已注释** | hbbs:21118 | Web Client WSS（不用） |
| ~~21119~~ | — | **已注释** | hbbr:21119 | Web Client WSS（不用） |

21118/21119 宿主机映射与 2.1 转发均已**注释/删除**；仅调试 Web Client 时再启用。

### 4.2 路由器（2.1）

#### 仍需转发（远控 + API）

| 端口 | 说明 |
|------|------|
| **21114** | TCP → `192.168.2.22` — API / 在线终端（明文 HTTP） |
| **21115–21117** | TCP/UDP → `192.168.2.22` — ID / 中继 |

#### 仅内网访问（DNS → 192.168.2.22，**不要**做公网 WAN 端口转发）

| 端口 | 说明 |
|------|------|
| **18444** | 管理后台 `/_admin/`（HTTPS，看在线终端） |

#### 2.1 上应删除的公网转发（不再使用）

| 端口 | 原用途 | 为何删 **公网转发** |
|------|--------|---------------------|
| **21118** | Web Client 注册 WSS | 不用 Web Client |
| **21119** | Web Client 中继 WSS | 同上 |

> **21114**：2.22 映射 `21114:21114`，**2.1 保留 WAN 转发**（你已确认）。明文 HTTP，凭据走 TLS 的 **18444/_admin/** 更安全。  
> 看活跃终端：`http://rustdesk.jackadam.top:21114`、内网 `http://192.168.2.22:21114`，或 **`18444/_admin/`**、脚本 `query-api-peers.py`。

详见 §5.4。

---

## 5. nginx 与 Web Client（不建议启用）

> **本仓库推荐策略：** 内网 **18444 → `/_admin/`** 做登录与用户/活动管理；**不使用 Web Client**。远控用桌面客户端。  
> §5.0–5.3 为 Web Client 技术说明，仅供曾调试时参考。

### 5.4 部署策略与安全（必读）

#### 推荐做法

| 项 | 做法 |
|----|------|
| **内网 18444** | 仅访问 `https://…:18444/_admin/` — 登录、用户/设备/活动管理 |
| **远控** | 使用 **桌面客户端**（21116/21117），不用浏览器 Web Client |
| **2.1 转发** | WAN 开 **21114、21115–21117**；**18444 仅内网 DNS**；删 **21118/21119** |
| **21114** | 宿主机映射 + **2.1 保留转发**；桌面客户端 **不 preset** `api_server`（可选，见 baixin） |
| **关闭 Web Client** | compose/nginx **注释** 21118/21119 |

#### 为什么不建议 Web Client

`lejianwen/rustdesk-api` 内置 **Web Client v1**（`/webclient/`）。上游 [Issue #415](https://github.com/lejianwen/rustdesk-api/issues/415) 与社区反馈：

| 风险 | 说明 |
|------|------|
| 登出后台 ≠ 登出 Web Client | 退出 `/_admin/` 后，浏览器 token 仍有效，仍可打开 `/webclient/` 远控 |
| 会话独立 | token 未过期前，知道 URL 即可尝试连接 |
| 无更好替代 | webclient2 已因 DMCA 删除 |

因此 **内网也不建议** 日常使用 Web Client；18444 只当管理入口，不当浏览器远控入口。

#### 21114：保留转发（明文 HTTP）

| 项 | 说明 |
|----|------|
| 作用 | rustdesk-api；**18444 后台与 21114 是同一服务** — 在线终端两边都能看 |
| 2.22 | 保留 `21114:21114` |
| 2.1 | **保留 WAN 转发** → `192.168.2.22:21114` |
| 风险 | 明文 HTTP，公网嗅探可窃听 token；敏感操作用 **18444/_admin/**（HTTPS） |
| 客户端 | 当前 **不** preset `api_server`（远控不依赖 API；需要时可填 `http://rustdesk.jackadam.top:21114`） |

2.22：在 2.22 主机上手动编辑 `docker-compose` / nginx，保留 21114，仅关 21118/21119（原 `scripts/apply-close-api-port-2.22.sh` 已移除）。

#### 若曾调试过 Web Client

§5.0–5.3 保留 WSS / +2 端口等技术说明；验收时可跳过 Web Client 项（§10）。

### 5.0 为什么非要 WSS，还要多开 nginx 端口？

三句话：

1. **Web 页是 HTTPS 打开的**，浏览器要求远程连接也用加密通道 → 必须是 **WSS**（带证书的 WebSocket），不能是明文 `ws://`。
2. **hbbs/hbbr 自带的 21118/21119 只有明文 WebSocket**，不会挂 SSL 证书 → 浏览器连不上。
3. **所以 nginx 在中间**：对外在 21118/21119 上提供 **WSS + 证书**，对内转成 hbbs/hbbr 的明文 ws。

```
浏览器  wss://域名:21118  （要证书）
           ↓
        nginx  终结 TLS
           ↓
        hbbs:21118  （明文 ws，只在 Docker 内网）
```

**为什么不能只用 18444 一个端口？**  
v1 **不会**读 `WS_HOST`，**不会**走 `18444/ws/id`。它只认一条规则：

```
WebSocket 端口 = ID/中继端口 + 2
```

我们配的是 `…:21116` / `…:21117`，所以算出来就是 **21118 / 21119**（不是源码里写死数字，而是 **+2 规则 + 标准端口** 的结果）。nginx 必须在算出来的端口上提供 WSS，不能只靠 18444。

**桌面客户端不受影响**：它连 21116/21117，不经过 21118，也不需要 WSS。

### 5.1 三个 HTTPS/WSS 入口

| 路径/端口 | 反代目标 | 使用者 |
|-----------|----------|--------|
| `:18444/` | rustdesk-api:21114 | 后台、Web Client 静态页 |
| `:18444/ws/id` | rustdesk-hbbs:21118/ | Web Client **v2** / 备用 |
| `:18444/ws/relay` | rustdesk-hbbr:21119/ | Web Client **v2** / 备用 |
| **`:21118` SSL** | rustdesk-hbbs:21118 | Web Client **v1（当前）** |
| **`:21119` SSL** | rustdesk-hbbr:21119 | Web Client **v1 中继** |

配置模板：[`scripts/rustdesk-nginx-default.conf`](../scripts/rustdesk-nginx-default.conf)

### 5.2 v1 Web Client 行为（必读）

当前 `lejianwen/rustdesk-api` 内置 Web Client **不读** `window.ws_host`，**不走** `/ws/id`。

登录后从 `localStorage['custom-rendezvous-server']`（如 `rustdesk.jackadam.top:21116`）计算：

```
注册 WebSocket：21116 + 2 → wss://rustdesk.jackadam.top:21118
中继 WebSocket：21117 + 2 → wss://rustdesk.jackadam.top:21119
```

因此 F12 里看到 `wss://…:21118` **是预期行为**；须 nginx 在该端口提供证书，不能裸暴露 hbbs。

自检：

```bash
curl -i -N -m 5 -k \
  -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
  -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
  https://rustdesk.jackadam.top:21118/
# 期望 HTTP/1.1 101 Switching Protocols
```

### 5.3 Web Client 排错

| 现象 | 原因 | 处理 |
|------|------|------|
| `wss://…:21118` failed / 1006 | 21118 无 TLS 或未转发 | nginx SSL 21118；查 2.1 转发 |
| 连接注册服务器失败 | 同上 | 硬刷页面（Ctrl+Shift+R） |
| 连接中继失败 | 21119 未通 | nginx SSL 21119 + 转发 |
| 仍连 `:21118` 但已配 `/ws/id` | v1 客户端逻辑 | 正常；修 21118 TLS 即可 |

连目标前：被控端 RustDesk **在线**、**网络就绪**、ID/Key 与服务器一致。

---

## 6. 环境变量与客户端对齐

### 6.1 `/storage/build/rustdesk/.env`

```env
DOMAIN=rustdesk.jackadam.top
ID_SERVER=rustdesk.jackadam.top
RELAY_SERVER=rustdesk.jackadam.top
ID_PORT=21116
RELAY_PORT=21117
NGINX_PORT=18444
JWT_KEY=<随机密钥>
```

### 6.2 API 容器环境（compose 内）

| 变量 | 值 | 说明 |
|------|-----|------|
| `RUSTDESK_API_RUSTDESK_ID_SERVER` | `rustdesk.jackadam.top:21116` | 同步到 Web Client localStorage |
| `RUSTDESK_API_RUSTDESK_RELAY_SERVER` | `rustdesk.jackadam.top:21117` | 同上 |
| `RUSTDESK_API_RUSTDESK_API_SERVER` | `https://rustdesk.jackadam.top:18444` | 页面与 API 基址 |
| `RUSTDESK_API_RUSTDESK_WS_HOST` | `wss://rustdesk.jackadam.top:18444` | **仅 v2**；v1 忽略 |
| `RUSTDESK_API_RUSTDESK_KEY_FILE` | `/app/conf/data/id_ed25519.pub` | 与 hbbs 同密钥 |

### 6.3 百信 Custom RustDesk 客户端（桌面）

`scripts/patch-lab/profiles/baixin.env` / GHA Issue 应对齐：

| preset 项 | 值 |
|-----------|-----|
| ID | `rustdesk.jackadam.top:21116` |
| 中继 | `rustdesk.jackadam.top:21117` |
| ~~API~~ | **留空**（可选 `http://rustdesk.jackadam.top:21114`；21114 已 **2.1 转发** 看终端） |
| 公钥 | 与 `id_ed25519.pub` 一致 |
| 超级密码 | `Jack@1993`（preset，**不是** API 后台密码） |

清配置重验：`scripts/clean-rustdesk-windows.ps1 -Force`

---

## 7. DNS 与 IPv6

| 场景 | 说明 |
|------|------|
| 内网 A 劫持 → 192.168.2.22 | 预期；桌面客户端可走 IPv4 |
| 内网 AAAA → 公网 `::22` | Windows 可能优先 IPv6；bridge 下已验证回包对称 |
| 内网仅验收 | 可临时钉 `192.168.2.22` 四项；或 2.1 去掉 AAAA |

抓包验证（2.22 上 eth0 UDP 21116）：`tcpdump -i eth0 -n udp port 21116 -c 20`

---

## 8. 数据、密钥与 API 后台

| 路径 | 说明 |
|------|------|
| `./data/server/` | hbbs/hbbr 数据；`id_ed25519`、`db_v2.sqlite3` |
| `./data/api/` | API SQLite `rustdeskapi.db` |
| 清库保留密钥 | 停容器后删 `data/server/db_v2.sqlite3` 等库文件，**勿删** `id_ed25519` |

**勿删 `id_ed25519`**：与 `BUILD_RS_PUB_KEY` / 已发客户端必须一致。

### API 管理员

| 项 | 说明 |
|----|------|
| 用户 | `admin` |
| 忘密码 | `docker exec rustdesk-api /app/apimain reset-admin-pwd '<新密码>'` |
| 查初始密码 | `docker logs rustdesk-api 2>&1 \| grep 'Admin Password'`（仅 Migrate 时打印） |

---

## 9. 运维脚本索引

| 脚本 | 用途 |
|------|------|
| [`rustdesk-docker-compose-bridge.yaml`](../scripts/rustdesk-docker-compose-bridge.yaml) | 推荐 compose 全文 |
| [`rustdesk-nginx-default.conf`](../scripts/rustdesk-nginx-default.conf) | nginx：18444 + 21118/21119 SSL |
| [`clean-rustdesk-windows.ps1`](../scripts/clean-rustdesk-windows.ps1) | Windows 清客户端配置 |

> 原 `scripts/` 下一次性排查脚本（抓包、query-hbbs、pull-release、trigger-gha 等）已清理；服务端健康检查与清库见上文各节 `docker` / `tcpdump` 命令。

---

## 10. 验收清单

### 服务端

- [ ] `docker ps` 四个容器 Up：hbbs、hbbr、api、nginx
- [ ] hbbs/hbbr 为 `rustdesk-int`，非 `host`
- [ ] 内网 `https://…:18444/_admin/` 可登录管理
- [ ] 2.1 **未**向公网转发 18444 / 21118 / 21119

### 桌面客户端（百信 R01）

- [ ] 域名四项 + 公钥；界面 **网络就绪**
- [ ] 日志 `request_pk received from …:21116`
- [ ] IPv6 域名路径抓包：回包源为 `::22`（非临时地址）

### Web Client（可选，**不建议**）

> 推荐 `RUSTDESK_API_APP_WEB_CLIENT=0`，跳过本节。

- [ ] （调试时）21118 WSS 101、`/webclient/` 可连 — 非生产验收项

---

## 11. 变更记录

| 日期 | 说明 |
|------|------|
| 2026-06-21 | hbbs/hbbr **host → bridge**；修复 IPv6 UDP 回包源地址不对称 |
| 2026-06-21 | nginx **21118/21119 SSL**；修复 Web Client v1 `wss://:21118` |
| 2026-06-21 | nginx `/ws/id` 改 bridge 服务名 + 路径剥离；API env 与 v1 行为对齐 |
| 2026-06-21 | 同步至 Outline：[RustDesk 自建栈（2.22 服务端）](https://wiki.jackadam.top/doc/rustdesk-222-nxus8Lz4rs) |
| 2026-06-21 | 2.22/2.1：**注释** 21118/21119；2.1 删除 Web Client WSS 转发 |

---

## 12. 相关文档

- [experiment-verification.md](./experiment-verification.md) — M1 客户端 exe 验收
- [verification-rollout.md](./verification-rollout.md) — 插针 rollout
- [workspace-handoff.md](./workspace-handoff.md) — 工作区交接
- [lejianwen/rustdesk-api Wiki — HTTPS 反向代理](https://github.com/lejianwen/rustdesk-api/wiki/HTTPS-Reverse-Proxy)
