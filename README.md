# ci-templates — 中央 CI/CD 模板仓库

全组织统一的流水线定义。各项目通过 GitHub Actions `workflow_call` 引用本仓库，
**流水线逻辑只维护这一份**，改这里 = 全部项目生效。

## 架构

```
push main / tag v*
      │
      ▼
GitHub Actions（引用本仓库 fullstack.yml）
  pytest / npm test ──→ 构建 Docker 镜像 ──→ push ghcr.io
      │                                        tag: <sha> + <env>-latest
      ▼
POST Dokploy deploy webhook
      │
      ▼
Dokploy（部署服务器）拉取 <env>-latest 镜像，滚动更新 Swarm 服务
```

- **触发策略（全自动）**：push `main` → staging；打 tag `v*` → production
- **回滚**：Dokploy 面板中将应用镜像 tag 从 `<env>-latest` 改为上一个 `<sha>` 重新部署（10 秒级）
- **镜像仓库**：ghcr.io（GitHub 自带，无需维护）

## 目录

```
.github/workflows/fullstack.yml   # 中央可复用流水线（核心资产，勿在项目内复制）
docker/backend.Dockerfile         # FastAPI 标准镜像模板
docker/frontend.Dockerfile        # Vue3 构建 → nginx 标准镜像模板
docker/nginx.conf                 # 前端 SPA nginx 配置模板
examples/project-ci.yml           # 项目接入示例（复制为项目的 .github/workflows/ci.yml）
```

项目如需自定义镜像，在自己的 `backend/Dockerfile` / `frontend/Dockerfile` 放文件即可，
流水线检测到后优先使用项目内的（中央模板是兜底）。

## 一、Dokploy 服务端初始化（一次性，约 30 分钟）

在部署服务器上（需 root）：

```bash
curl -sSL https://dokploy.com/install.sh | sh
```

安装脚本会自动：初始化 Docker Swarm → 部署 Traefik(80/443) → 启动 Dokploy 面板(:3000)。

> **端口冲突注意**：若宿主机已有 nginx/frpc 占用 80，需先处理（见 FAQ-1）。

安装后：

1. 浏览器访问 `http://<服务器IP>:3000`，创建管理员账号
2. **配置 ghcr 凭证**：Settings → Registries → Add Registry
   - Registry URL: `ghcr.io`
   - Username: GitHub 用户名
   - Password: GitHub PAT（勾 `read:packages` 权限）
3. （可选）Settings → Certificates 配置域名 + Let's Encrypt，否则应用用 IP:端口访问

## 二、每个项目的接入清单（约 10 分钟/项目）

1. **整理仓库结构**为 `backend/` + `frontend/`（本模板约定的单仓结构）
2. **复制 `examples/project-ci.yml`** 为项目仓库 `.github/workflows/ci.yml`，
   修改 `project-name`（两处），把 `YOUR-ORG` 替换为组织名
3. **Dokploy 面板创建应用**（每个项目 1-2 个）：
   - Create Application → 类型 Docker
   - 镜像：`ghcr.io/<org>/<project-name>-backend:staging-latest`
   - 环境变量：在面板 Environment 页填（**密钥只存这里，不进仓库**）
   - 复制应用的 **Deploy Webhook URL**
4. **GitHub 仓库配置变量**：Settings → Secrets and variables → Actions → Variables
   - `DOKPLOY_STAGING_WEBHOOK` = 上一步的 staging 应用 webhook
   - `DOKPLOY_PROD_WEBHOOK` = production 应用 webhook（如需生产环境，单独建应用，tag 用 `production-latest`）
5. **首次验证**：push 一个 commit 到 main → 观察 Actions 全绿 → Dokploy 面板看到容器更新
6. **验证回滚**：面板把镜像 tag 改成上一个 sha → Redeploy → 确认服务正常 → 改回 `staging-latest`
7. 旧 CI 脚本保留一个迭代周期，确认稳定后删除

纯后端项目在 ci.yml 的 `with:` 中加 `has-frontend: false`；纯前端反之。

## 三、日常运维

| 操作 | 入口 |
|---|---|
| 查日志 | Dokploy 面板 → 应用 → Logs（或 `docker service logs`） |
| 改环境变量 | Dokploy 面板 → 应用 → Environment → Save（自动重建） |
| 回滚 | 面板改镜像 tag 为旧 sha → Redeploy |
| 紧急绕开 CI 上线 | 服务器上 `docker service update --image ... <service>`（事后补 tag） |
| 监控告警 | Dokploy 自带通知；建议另装 Uptime Kuma 做探活 |

## FAQ

**1. 服务器 80/443 被宿主机 nginx/frpc 占用怎么办？**
三选一：a) 把现有站点迁移进 Dokploy 后停掉宿主机 nginx（推荐，长期最干净）；
b) 宿主机 nginx 反代 `*.internal` 域名到 Dokploy Traefik 的自定义端口；
c) 另用一台干净机器做 Dokploy manager，本机仅作 Swarm worker。

**2. ghcr.io 拉取慢？**
先在服务器实测：`curl -s -o /dev/null -w "%{time_total}s\n" https://ghcr.io/v2/`。
若明显慢，备选：阿里云 ACR 个人版（免费）或自建 Harbor，仅需改 fullstack.yml 的
`REGISTRY` 和 login 步骤，项目侧零改动——这就是中央模板的价值。

**3. 镜像 tag 策略？**
每次构建打两个 tag：`<git-sha>`（不可变，回滚用）和 `<env>-latest`（部署用）。
Dokploy 应用固定引用 `<env>-latest`，webhook 触发后重新拉取即为新版本。

**4. 测试在 CI 挂了但想强制部署？**
不允许。流水线设计为测试全绿才构建镜像。修测试，或确认是基础设施抖动后
在 Actions 页面 Re-run。

**5. 现有 docker-compose 项目如何迁移？**
不需要一次性迁移。新项目/下次发版的项目优先走本流程，老项目按
"接入清单"逐步迁移，迁移一个删一个旧 compose。
