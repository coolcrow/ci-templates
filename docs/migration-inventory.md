# 存量项目部署现状盘点（迁移台账）

> 盘点时间：2026-08-27。迁移原则：**理解现状 → 逐个迁移 → 迁移一个释放一个旧端口**。
> 每完成一行就在"状态"列打勾，并更新日期。

## ⚠️ 盘点发现的风险（优先处理）

1. **3 个容器没有重启策略（restart=no），服务器重启后不会自动恢复**：
   - `home-delivery-redis-1`（home-delivery 的缓存/队列）
   - `portrait-mysql-1`、`portrait-redis-1`（portrait 的数据库和缓存）
   → 这就是"重启影响部署"的隐患源头。迁移时由 Dokploy 接管即自动解决；
     未迁移前可临时修复：`docker update --restart unless-stopped <容器名>`
   （2026-08-28 复核：portrait 的 mysql 实际已迁共享实例——compose 指向
   mysql-shared，portrait-mysql-1 是零表空壳孤儿容器 + 200MB 卷，重启策略
   已是 unless-stopped；迁移 #8 时可顺手清理孤儿容器和卷，待用户确认）
2. **mysql-shared 把 3306 和 3307 同时暴露到 0.0.0.0**：多项目共享库 + 双端口暴露，
   内网可接受但建议迁移期收敛为仅 127.0.0.1 或集群内访问
3. **5 个独立 frpc 容器**（frpc-deploy/frpc-hd/frpc-nc/frpc-mall/ps-frpc）：
   是公网入口隧道，迁移项目时**必须同步改 frp 配置**指向新端口/域名，否则外网断流

## compose 项目（9 个，按建议迁移顺序）

| 顺序 | 项目 | 目录 | 容器构成 | 当前端口 | 复杂度 | 状态 |
|---|---|---|---|---|---|---|
| 1 | captureli-license | /home/coz/captureli-license | 单服务 | 127.0.0.1:8401 | ★ 试点首选 | ✅ 2026-08-27 |
| 2 | inven-monitor | /home/coz/inven-monitor | 单后端 | 127.0.0.1:8400 | ★ | ✅ 2026-08-27 |
| 3 | polystudio | /home/coz/polystudio | 单后端 | 127.0.0.1:8310 | ★ | ✅ 2026-08-27 |
| 4 | name_culture | /home/coz/name_culture | 后端+redis | 127.0.0.1:8500 | ★★ | ✅ 2026-08-28 |
| 5 | pymall-intranet | /home/coz/pymall | 单后端 | 0.0.0.0:9200 | ★★ 有 frpc | ✅ 2026-08-28 |
| 6 | weixin-article-publisher | /home/coz/weixin-article-publisher | publisher+dailyhot | 0.0.0.0:8001 | ★★ | ✅ 2026-08-28 |
| 7 | home-delivery | /home/coz/home-delivery | api+celery×2+redis | 0.0.0.0:8100 | ★★★ celery | ✅ 2026-08-28 |
| 8 | portrait | /home/coz/portrait | 后端+celery+redis | 0.0.0.0:8200 | ★★ | ⬜ |
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

### polystudio 迁移备忘（2026-08-27 完成，零停机切换）

- 仓库：coolcrow/PolyStudio（已有 git 历史与 CI，未重推全量）
- Dokploy：project=polystudio / composeId=7n7X9ffyO1e6gSGDF_gcj
- 流水线拆分：**后端走中央流水线（backend-cd.yml）**；前端仍走 deploy.yml 的
  cvm-edge job（GH runner 构建 → scp → CVM 静态托管），两条链路并存
- 原 ci.yml 恢复为测试流水线（前端 + PR 后端门禁），中央流水线在 backend-cd.yml
- 数据：外部卷 polystudio_storage_data（129M 生成媒体）零拷贝共享；MySQL 专用账号
  polystudio@mysql-shared
- frp：ps-frpc 经 docker 网络别名 `ps_backend:8000` 直连（非宿主端口）——
  新容器接入同一外部网络 polystudio_polystudio_internal 并接管别名，frp 配置零改动
- 切换方式：新容器先以 ps_backend_new 别名 + 8311 并行验证 → 停旧 → 改别名/端口
  重部署，**停机仅 3 秒**（生产服务推荐此模式）
- 首次部署 ghcr 拉取极慢（1.7GB 镜像 ~1MB/min，凌晨时段）：改用服务器本地构建镜像
  + 临时去 pull_policy 完成首部署；
  ✅ 已修复并实测验证（08-28）：完整组合 = 中央模板构建后 `--load` 落本机 daemon
  （bc80967）+ compose `pull_policy: missing`（三项目已统一修改）——实测容器
  3 秒重建、镜像 ID 与 CI 构建产物一致，ACR 方案不再需要；
  原理备注：--load 导出未压缩层，digest 与 ghcr 压缩 blob 不匹配，故
  pull_policy: always 的 "Already exists" 命中不了本地构建层（实测大层仍重新下载），
  必须用 missing 让 compose 直用本地 tag 跳过拉取
  ⚠️ 夜间 github.com 劣化会拖垮 runner checkout（08-28 01:00-01:58 实测中断，
  验证运行因此重跑过一次）；Mac 本机代理 127.0.0.1:7897 可用，服务器经 LAN
  （192.168.31.98:7897）待代理开启 Allow LAN 后可配 git http proxy
- 旧 deploy.yml 的 intranet-backend job（CVM 跳板 SSH 构建）已移除
- 中央模板新增 test-apt-packages 输入（cv2 测试需要 libgl1，f12ede0）
- 旧 compose：已 stop 未 down，观察 1-2 天后清理（ps-frpc 依赖的
  polystudio_polystudio_internal 网络不会被 down 移除，新容器仍在用）
- ✅ 安全加固（08-28）：remote URL 已去除内嵌 PAT（改干净 URL，服务器推送走
  credential helper 注入，不入配置文件）；
  ⚠️ 该全权限 PAT 本身仍有效，需在 GitHub → Settings → Developer settings →
  Tokens 手动吊销轮换（无法代操作，属账号级操作）

### name_culture 迁移备忘（2026-08-28 完成，7 秒切换）

- 仓库：coolcrow/name_culture（新建私有仓库 + git 化首推，211 文件）
- Dokploy：project=name_culture / composeId=3VkpvqqToHpvj3qZJPSc5
- 双服务：backend + redis（128mb LRU 缓存）；MySQL 走共享实例（root 账号）
- 数据：bind mount 绝对路径零拷贝（static 1.9M / data 16K / redis RDB 12K）
- frp：frpc-nc 127.0.0.1:8500 → CVM 8095 → nc_nginx → name-culture.aibolt.tech，零改动
- 切换：8501 并行验证（health/db/redis 全绿）→ 停旧双容器 → 8500 + redis
  数据目录 + APP_NAME 修正 → **7 秒恢复**，公网 200
- 测试修复：get_mp_access_token 测试 patch get_sync 隔离 DB 依赖（CI 无库环境
  下连接错误先于凭证检查抛出）
- ⚠️ Dokploy 注入坑：Dokploy 会向 compose 的 .env 注入 APP_NAME=<appName>，
  覆盖 pydantic 默认值——app_name 有展示意义的项目需在 environment 显式声明
- 网络事件：测试修复推送撞上第二轮 github.com 中断（08-28 02:45+），经
  Mac LAN 克隆服务器仓库 + 本机代理中转推送解决；runner checkout 抓到窗口幸存
- 旧 compose：已 stop 未 down（backend+redis），观察后清理

### pymall-intranet 迁移备忘（2026-08-28 完成，6 秒切换）

- 仓库：coolcrow/pymall（新建私有仓库 + git 化首推，234 文件）
- Dokploy：project=pymall / composeId=jMBH89rv1ZtE4wbdiu0oD
- 范围：仅内网 API 容器（web/admin/h5 留在 CVM 全栈 compose；admin-web/h5 构建
  走存量 CI 的 GH-hosted job，backend job 改 PR-only 避免与中央流水线重复）
- 数据：bind mount 绝对路径零拷贝（certs 12K / backups 44K / uploads 2.2M）
- frp：frpc-mall 经 **172.17.0.1:9200**（docker0 网关而非 127.0.0.1）→ CVM 8097
  → mall.aibolt.tech——新容器保持 0.0.0.0:9200 绑定即**零 frp 改动**
  （台账原担心的"必须同步改 frp"在保持端口绑定的前提下不需要）
- 切换：9201 并行验证 → 停旧 → 9200 → **6 秒恢复**，公网 200（frp 链路实测）
- 测试：SQLite 内存库（StaticPool，无需 MySQL job）；test-apt-packages:
  fonts-noto-cjk（海报渲染中文字体，存量 CI 同款依赖）
- 坑：`git commit -am` 不包含新文件——backend-cd.yml 首次漏提（workflow 未注册），
  补提解决；新文件必须显式 git add
- 旧容器：pymall-api-intranet 已 stop 未 down

### weixin-article-publisher 迁移备忘（2026-08-28 完成，3 秒切换）

- 仓库：coolcrow/weixin-article-publisher（新建私有仓库 + git 化，242 文件）
- Dokploy：project=weixin-article-publisher / composeId=hT_tLf9G8cUZoq9SNYeqL
- 双服务：publisher（构建型，源码根目录）+ dailyhot（imsyy/dailyhot-api 现成镜像，
  容器网络 DNS 互访 http://dailyhot:6688）
- **无 frp**：纯内网服务，Chrome 扩展（extension/ 源码在仓库）经
  http://192.168.31.114:8001 直连，保持 0.0.0.0 绑定即零改动
- MySQL：host.docker.internal（host-gateway）→ 宿主 mysql-shared，
  extra_hosts 保持原配置零改动；whisper 死 URL（deferred）保持原样
- 切换：8002 并行验证（health + dailyhot 网络互通）→ 停旧双容器 → 8001
  → **3 秒恢复**
- 测试：conftest 增加 TEST_DB_URL 解析（中央模板 MySQL job 约定，同 inven-monitor），
  测试库 article_app_test；needs-mysql: true
- 坑①：Dockerfile `COPY .env .` 在 CI 必挂（.env 被 gitignore）——改 `.env*` 通配，
  运行期配置以容器 env 为准
- 坑②：ssh heredoc 嵌套引号会被 shell 吃掉引号导致脚本挂（且 git add 在补丁失败后
  仍执行，把 extension.pem 私钥暂存了，幸未提交）——多行补丁一律走本地编辑 + scp
- ⚠️ 安全备注：JWT_SECRET=your-jwt-secret-change-me（弱占位符）在生产运行，
  建议轮换（会使现有登录 token 失效，需用户择机操作）
- 独立容器 dailyhotapi（0.0.0.0:6688）不属于本 compose，未动
- 旧 compose：已 stop 未 down（publisher+dailyhot 双容器）

### home-delivery 迁移备忘（2026-08-28 完成，6 秒切换，首个 celery 项目）

- 仓库：coolcrow/home-delivery（已有历史仓库，**master 分支**保持原约定；同步了
  服务器侧 17 天漂移 + migrations SQL 首次入库）
- Dokploy：project=home-delivery / composeId=RZe4zbC5m-M5mBAxTGJri
- 四服务：api + celery-worker + celery-beat + redis——worker/beat 与 api 同镜像
  不同 command；切换前检查 redis 队列深度（=0 无损窗口）
- 切换：8101 四容器并行验证（worker Connected/ready + beat 调度正常）→
  停旧 → 8100 + redis 6380 → **6 秒恢复**；frp（frpc-hd 8100→8090）零改动
- 测试修复（22→6→0 三轮）：根因是**生产库手动加列**（coach_cash/car_cash/
  cash_status）而模型/迁移/测试内联 DDL 全没跟上——修复 = 测试 DDL 对齐生产
  列集 + 种子/断言从 amount 迁到 cash/coach_cash 语义
- pyproject 修复：setuptools 显式包发现（app*，多顶层目录下 pip install . 必炸）
  + fakeredis 移入主依赖（测试容器直跑）
- ✅ 代理方案（08-28 定稿）：三层覆盖——①宿主侧 ~/.gitconfig + /etc/gitconfig；
  ②runner 容器侧由中央模板注入 job env HTTPS_PROXY/HTTP_PROXY/NO_PROXY（263f383，
  容器内 git/pip 确定性走代理，不依赖 runner 的 HOME/gitconfig 拷贝机制——该机制
  时灵时不灵，job env 是唯一可靠注入通道）；③验证运行 33143189447 全绿且日志
  实锤 env 已注入 step 环境。前提是 Mac 代理在线——CI 只在 push 后运行而 push
  必然来自开着的 Mac，天然满足；Mac 换 IP 需改模板 proxy 默认值（建议绑静态 IP）
- 数据：static bind mount（1.8M）零拷贝；MySQL 专用账号 hd@mysql-shared
- 旧 compose：已 stop 未 down（api/worker/beat/redis 四容器）
