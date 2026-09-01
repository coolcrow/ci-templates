# 部署服务器 Dokploy 安装记录

服务器：`coz@192.168.31.114`（Ubuntu 22.04，Docker 28.3.1，29G 内存）
安装时间：2026-08-27，使用官方脚本（/tmp/dokploy-install.sh，ADVERTISE_ADDR=192.168.31.114）

## 组件

| 组件 | 类型 | 镜像 | 端口 |
|---|---|---|---|
| dokploy | Swarm service (manager 约束) | dokploy/dokploy:latest | 3000（面板） |
| dokploy-postgres | Swarm service (manager 约束) | postgres:16 | 仅集群内 |
| dokploy-traefik | 独立容器 (--restart always) | traefik:v3.6.7 | 80/443 |
| registry-mirror | 独立容器 (--restart unless-stopped) | registry:2 | 5001（docker.io 穿透缓存） |

- registry-mirror：**全平台 CI 构建的关键依赖**（2026-09-02 daocloud 公共镜像源对匿名请求 401 死亡后上线）。
  配置 `~/registry-mirror/config.yml`（proxy.remoteurl=registry-1.docker.io），容器带
  `HTTP_PROXY/HTTPS_PROXY=http://192.168.31.98:7897` 拉上游，blob 缓存在卷 `registry-mirror-data`。
  buildkitd/daemon 经 `http://192.168.31.114:5001` 匿名访问（LAN 内，需 http=true）。
  **勿当无名容器清理**；删除 = 全平台 FROM docker.io 的构建瘫痪。

- 数据目录：`/etc/dokploy`（traefik 配置、应用配置）
- 密钥：Docker Secrets（dokploy_postgres_password / dokploy_auth_secret），未落明文
- 面板入口：http://192.168.31.114:3000（首次访问创建管理员账号）

## 重启行为（已验证/配置）

- Docker daemon：systemd enabled，重启自动拉起
- Swarm services（dokploy/postgres）：随 daemon 自动恢复
- traefik：`--restart always`
- registry-mirror：`--restart unless-stopped`（独立容器，随 daemon 自动恢复）
- **apache2 已 stop + disable**（原占 80 端口的默认空站点，确认无业务后清除，
  配置仍在 /etc/apache2，如需回滚 `systemctl enable --now apache2`）

## 端口分配约定（迁移期）

- 80/443：Dokploy Traefik（新部署项目的统一入口）
- 8100-9200 段：存量 docker-compose 项目（迁移一个释放一个）
- 3000：Dokploy 面板；3306/3307：mysql-shared（待收敛）
- 5001：registry-mirror（docker.io 穿透缓存，CI buildx / daemon 拉流专用）

## REST API（已验证可用）

- Base URL：`http://192.168.31.114:3000/api`，tRPC 风格：`/api/<router>.<procedure>`
- 认证：`x-api-key` 请求头；Key 已存服务器 `~/dokploy-api-key`（600）
- 已确认路由：project / application / registry / server / user / deployment / domain
- 交互式文档 `/api/reference` 需浏览器会话（面板登录后访问）
- 用途：程序化建 project/application、写环境变量、触发部署、回滚——迁移操作全部走 API，不碰 UI

## Self-hosted Runner（部署服务器内网，GitHub 托管 runner 无法回调）

- 安装位置：`/home/coz/actions-runner-captureli`（systemd 服务，随开机自启）
- 绑定仓库：coolcrow/captureli-license（用户账号无 org 级 runner，每仓库一个实例）
- 项目 ci.yml 传 `runner: self-hosted`
- 第二个实例：`/home/coz/actions-runner-inven-monitor`（coolcrow 无 sudo，改用
  `systemctl --user` + linger 常驻，服务名 actions-runner-inven-monitor.service；
  新仓库接入照此模式即可，程序目录可直接 cp 自已有实例后重新 config）

### 国内网络适配（已内置在中央模板）

| 问题 | 解法 |
|---|---|
| setup-python/node 工具下载极慢（50KB/s） | 测试改为容器内运行（python:3.12 / node:20），daemon 拉取（daocloud 死后自动回退 daemon 代理直连，实测可用） |
| buildx 容器不继承 daemon mirror，FROM docker.io 超时 | setup-buildx-action 传 config-inline：docker.io → `192.168.31.114:5001`（自建 LAN registry-mirror；2026-09-02 daocloud 对匿名请求 401 死亡，公共镜像源全灭） |
| buildkitd 的 token 拉取器不走 env 代理（driver-opts `env.HTTPS_PROXY` 无效，v0.17/0.19/0.23 实测直连被污染 IP 超时） | 唯一可靠路径 = LAN registry-mirror；env 代理仅对 RUN 步骤内的 pip 等外联有用 |
| daemon.json 仍残留已死的 daocloud mirror | 拉取实测可回退 daemon 代理直连（hello-world OK）；清理需 root，非紧急 |
| 容器内测试以 root 落盘，宿主 job 无法 checkout | 测试 job 末尾 `chmod -R a+rwX .` |
| pip/npm 慢 | runner=self-hosted 时自动切清华 pip 源 / npmmirror |
| git push github.com 偶发 TLS/超时 | 重试即可（脚本内置 5 次重试） |
| ghcr.io 拉取 364MB 约 1-2 分钟 | 可接受；后续可换 ACR 优化 |

## Dokploy 部署机制（实测）

- Compose 部署命令：`docker compose up -d --build --remove-orphans`
- **pull_policy 策略（08-28 更新，替代旧的 `always` 教义）**：ghcr.io 从国内拉取实测
  停滞（1.7GB 镜像 ~1MB/min），`pull_policy: always` 会让部署卡死数小时。
  正确组合 = 中央模板 self-hosted 构建后 `--load` 落本机 daemon（bc80967）+
  compose `pull_policy: missing`——tag 已被 --load 刷新为最新构建，compose 直接
  使用本地镜像，实测容器 3 秒重建。daemon 无镜像时（新机）退回慢拉取，属可接受兜底。
  注意：--load 导出的是未压缩层，digest 与 ghcr 压缩 blob 不匹配，故 `always` 的
  "Already exists" 命中不了本地构建层，必须用 `missing` 跳过拉取。
- 镜像内容没变时容器不会重建（compose 判定无变化）——正常且高效
- 部署日志：宿主机 `/etc/dokploy/logs/<appName>/` 下按时间戳分文件
- webhook 路径格式：`POST /api/deploy/compose/<refreshToken>`（token 是路径参数）；
  实测可用，但中央模板默认走更明确的 `POST /api/compose.deploy {"composeId"}` + x-api-key

## 后续手动步骤

1. ~~面板创建管理员账号~~ ✅（API Key 已配置：~/dokploy-api-key）
2. ~~ghcr registry 凭证~~ ✅（ghcr-coolcrow，PAT 已配）
3. 按 migration-inventory.md 顺序逐个迁移项目（captureli-license 已完成 ✅）
4. 全部迁移完成后：`apt purge apache2` 清理残留
5. ~~建议整改：polystudio git remote 里的全权限 PAT 轮换~~ ✅ 已完成（08-28）：
   旧全权限 PAT 已吊销；服务器 ~/github-pat 更换为**细粒度最小权限 token**
   （仅 Contents RW、限定 10 个部署仓），读写已实测验证。
