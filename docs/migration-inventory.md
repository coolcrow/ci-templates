# 存量项目部署现状盘点（迁移台账）

> 盘点时间：2026-08-27。迁移原则：**理解现状 → 逐个迁移 → 迁移一个释放一个旧端口**。
> 每完成一行就在"状态"列打勾，并更新日期。

## ⚠️ 盘点发现的风险（优先处理）

1. **3 个容器没有重启策略（restart=no），服务器重启后不会自动恢复**：
   - `home-delivery-redis-1`（home-delivery 的缓存/队列）
   - `portrait-mysql-1`、`portrait-redis-1`（portrait 的数据库和缓存）
   → 这就是"重启影响部署"的隐患源头。迁移时由 Dokploy 接管即自动解决；
     未迁移前可临时修复：`docker update --restart unless-stopped <容器名>`
2. **mysql-shared 把 3306 和 3307 同时暴露到 0.0.0.0**：多项目共享库 + 双端口暴露，
   内网可接受但建议迁移期收敛为仅 127.0.0.1 或集群内访问
3. **5 个独立 frpc 容器**（frpc-deploy/frpc-hd/frpc-nc/frpc-mall/ps-frpc）：
   是公网入口隧道，迁移项目时**必须同步改 frp 配置**指向新端口/域名，否则外网断流

## compose 项目（9 个，按建议迁移顺序）

| 顺序 | 项目 | 目录 | 容器构成 | 当前端口 | 复杂度 | 状态 |
|---|---|---|---|---|---|---|
| 1 | captureli-license | /home/coz/captureli-license | 单服务 | 127.0.0.1:8401 | ★ 试点首选 | ✅ 2026-08-27 |
| 2 | inven-monitor | /home/coz/inven-monitor | 单后端 | 127.0.0.1:8400 | ★ | ✅ 2026-08-27 |
| 3 | polystudio | /home/coz/polystudio | 单后端 | 127.0.0.1:8310 | ★ | ⬜ |
| 4 | name_culture | /home/coz/name_culture | 后端+redis | 127.0.0.1:8500 | ★★ | ⬜ |
| 5 | pymall-intranet | /home/coz/pymall | 单后端 | 0.0.0.0:9200 | ★★ 有 frpc | ⬜ |
| 6 | weixin-article-publisher | /home/coz/weixin-article-publisher | publisher+dailyhot | 0.0.0.0:8001 | ★★ | ⬜ |
| 7 | home-delivery | /home/coz/home-delivery | api+celery×2+redis | 0.0.0.0:8100 | ★★★ celery | ⬜ |
| 8 | portrait | /home/coz/portrait | 后端+celery+mysql+redis | 0.0.0.0:8200 | ★★★ 自带 mysql | ⬜ |
| 9 | mysql-shared | /home/coz/mysql-shared | 共享 MySQL | 3306/3307 | ★★★ 依赖方多 | ⬜ 最后 |

## 独立容器（非 compose，需逐一确认归属）

| 容器 | 镜像 | 说明 | 处置 |
|---|---|---|---|
| frpc-deploy / frpc-hd / frpc-nc / frpc-mall / ps-frpc | snowdreamtech/frpc | 公网隧道 | 保持独立，迁移项目时改配置 |
| minio | - | 对象存储 | 保持独立或迁入 Dokploy（有官方模板） |
| dailyhotapi | imsyy/dailyhot-api | 公共服务 API | 可迁入 Dokploy（低优先） |
| xboard | ghcr.io/cedar2025/xboard | 面板（6 个 bind 挂载） | 保持独立，不动 |

## 每个项目的迁移流程（通用）

1. 读项目目录的 compose 文件 + .env，记录：镜像构建方式、环境变量、volume、依赖（mysql/redis/frp）
2. 仓库接入中央流水线（复制 examples/project-ci.yml，改 project-name）
3. Dokploy 建 Compose 服务（镜像 ghcr.io/coolcrow/<name>-backend:staging-latest，
   **service 里必须加 `pull_policy: always`**，volume 用 external 挂旧卷保数据）
4. 仓库配置 secret `DOKPLOY_API_KEY` + 变量 `DOKPLOY_API_URL`（或复用账号级配置）
5. ci.yml 填 `dokploy-compose-id`（Dokploy API 创建后返回的 composeId）
6. 验证新部署健康（日志 + 接口探活）
7. **有 frp 的项目**：改 frpc 配置指向新入口，验证外网访问
8. 停旧 compose（`docker compose stop`，先不删），观察 1-2 天
9. 确认稳定后 `docker compose down`，释放旧端口，台账打勾

### captureli-license 迁移备忘（试点，2026-08-27 完成）

- 仓库：coolcrow/captureli-license（私有，源码已 git 化推送）
- Dokploy：project=captureli / composeId=xs70P1RqjF0qhvD6UKh8w
- 数据：外部卷 captureli-license_license_data（licenses.db 原样保留，零拷贝）
- frp：frpc-hd 127.0.0.1:8401 → 公网 8094，配置零改动
- 已知问题：WECHAT_MERCHANT_PRIVATE_KEY_PEM 路径悬空（/home/ubuntu/...，迁移前就存在，
  如启用微信支付需提供 pem 并放入数据卷后改 env）
- 遗留：production job 目前复用 staging 的 composeId；启用 tag 发布时需为生产单独建
  compose 服务（image 用 production-latest）并替换变量

### inven-monitor 迁移备忘（2026-08-27 完成）

- 仓库：coolcrow/inven-monitor（私有，源码已 git 化推送，main 分支）
- Dokploy：project=inven-monitor / composeId=xMcuwc4YGWkWn_08jsTar
- 数据：外部卷 inven-monitor_certs_data + inven-monitor_uploads_data 原样保留
- 数据库：共享 mysql-shared（192.168.31.114:3306/inven_monitor），Dokploy env 里
  DATABASE_URL 显式指向 192.168.31.114（不能用 .env 里的 127.0.0.1）
- frp：frpc-hd 127.0.0.1:8400 → 公网 8093（inven-monitor.aibolt.tech），配置零改动
- runner：/home/coz/actions-runner-inven-monitor（coolcrow 无 sudo 权限，改用
  systemd --user + linger 常驻；captureli 的 runner 是系统级服务，两者并存）
- conftest 改造：TEST_DB_URL 支持环境变量注入 + 会话级自动建 schema（对齐
  scripts/init_test_db.py），中央模板的 test-backend-mysql job 可直接跑
- ✅ 测试已修复（同日 90e6b70）：16 个陈旧断言更新至 v2 商业模式语义，
  全量 671 passed + 1 xfail（xfail 记录已知 bug：员工注册未校验 from_store 租户类型，
  传品牌 id 会把员工建进品牌租户，待修）
- ⚠️ 存量问题（迁移前 2026-08-25 即存在，非迁移引入）：启动 bootstrap 报
  "Multiple rows were found when one or none was required"，非致命（被捕获、服务正常）；
  已排除超管/套餐/邀请码/演示数据等全部 scalar_one 查找，精确定位需给 bootstrap.py
  的 logger.error 加 exc_info 后重启看 traceback
- 备注：测试套件较慢（db fixture 每用例 TRUNCATE 全部 45 张表，全量 12-45 分钟，
  磁盘压力大时显著变慢），后续可按模块声明依赖表优化
- 旧 compose：已 stop 未 down（docker-compose.intranet.yml），观察 1-2 天稳定后
  `docker compose -f docker-compose.intranet.yml down` 清理（8400 端口已被新服务占用，无冲突）
