# 部署服务器 Dokploy 安装记录

服务器：`coz@192.168.31.114`（Ubuntu 22.04，Docker 28.3.1，29G 内存）
安装时间：2026-08-27，使用官方脚本（/tmp/dokploy-install.sh，ADVERTISE_ADDR=192.168.31.114）

## 组件

| 组件 | 类型 | 镜像 | 端口 |
|---|---|---|---|
| dokploy | Swarm service (manager 约束) | dokploy/dokploy:latest | 3000（面板） |
| dokploy-postgres | Swarm service (manager 约束) | postgres:16 | 仅集群内 |
| dokploy-traefik | 独立容器 (--restart always) | traefik:v3.6.7 | 80/443 |

- 数据目录：`/etc/dokploy`（traefik 配置、应用配置）
- 密钥：Docker Secrets（dokploy_postgres_password / dokploy_auth_secret），未落明文
- 面板入口：http://192.168.31.114:3000（首次访问创建管理员账号）

## 重启行为（已验证/配置）

- Docker daemon：systemd enabled，重启自动拉起
- Swarm services（dokploy/postgres）：随 daemon 自动恢复
- traefik：`--restart always`
- **apache2 已 stop + disable**（原占 80 端口的默认空站点，确认无业务后清除，
  配置仍在 /etc/apache2，如需回滚 `systemctl enable --now apache2`）

## 端口分配约定（迁移期）

- 80/443：Dokploy Traefik（新部署项目的统一入口）
- 8100-9200 段：存量 docker-compose 项目（迁移一个释放一个）
- 3000：Dokploy 面板；3306/3307：mysql-shared（待收敛）

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
| setup-python/node 工具下载极慢（50KB/s） | 测试改为容器内运行（python:3.12 / node:20），镜像走 daemon 的 daocloud 加速 |
| buildx 容器不继承 daemon mirror，FROM docker.io 超时 | setup-buildx-action 传 config-inline：docker.io → docker.m.daocloud.io |
| 容器内测试以 root 落盘，宿主 job 无法 checkout | 测试 job 末尾 `chmod -R a+rwX .` |
| pip/npm 慢 | runner=self-hosted 时自动切清华 pip 源 / npmmirror |
| git push github.com 偶发 TLS/超时 | 重试即可（脚本内置 5 次重试） |
| ghcr.io 拉取 364MB 约 1-2 分钟 | 可接受；后续可换 ACR 优化 |

## Dokploy 部署机制（实测）

- Compose 部署命令：`docker compose up -d --build --remove-orphans`
- **service 必须写 `pull_policy: always`**，否则不拉新的 latest tag
- 镜像内容没变时容器不会重建（compose 判定无变化）——正常且高效
- 部署日志：宿主机 `/etc/dokploy/logs/<appName>/` 下按时间戳分文件
- webhook 路径格式：`POST /api/deploy/compose/<refreshToken>`（token 是路径参数）；
  实测可用，但中央模板默认走更明确的 `POST /api/compose.deploy {"composeId"}` + x-api-key

## 后续手动步骤

1. ~~面板创建管理员账号~~ ✅（API Key 已配置：~/dokploy-api-key）
2. ~~ghcr registry 凭证~~ ✅（ghcr-coolcrow，PAT 已配）
3. 按 migration-inventory.md 顺序逐个迁移项目（captureli-license 已完成 ✅）
4. 全部迁移完成后：`apt purge apache2` 清理残留
5. 建议整改：polystudio git remote 里的全权限 PAT 轮换（已在服务器 ~/github-pat 留档）
