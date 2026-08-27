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

## 后续手动步骤

1. 面板创建管理员账号（http://192.168.31.114:3000）
2. 生成 API Key 并存入服务器 ~/dokploy-api-key
3. Settings → Registries 添加 ghcr.io（GitHub 用户名 + PAT 勾 read:packages）
4. 按 migration-inventory.md 顺序逐个迁移项目
5. 全部迁移完成后：`apt purge apache2` 清理残留
