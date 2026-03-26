# 修改记录

上游仓库：`https://github.com/lizhipay/acg-faka.git`
修改分支：`nsfe`

本文件记录修改分支相对于原项目的所有改动。上游更新时以此为对照清单，逐条检查：

- **bug 修复**类改动：检查上游是否已修复，若已修复则标记为 `已修复(可移除)` 并移除补丁
- **需求定制**类改动：检查上游更新是否与该改动冲突，若冲突需手动合并

每项改动格式：

```
### <序号>. <简要标题>

- **类型**：bug 修复 / 需求定制
- **文件**：`path/to/file`
- **描述**：做了什么、为什么要改
- **上游状态**：未修复 / 已修复(可移除) / 不适用
```

- **类型**：`bug 修复` = 原项目缺陷；`需求定制` = 个人需求改动
- **上游状态**：每次上游同步后更新。`未修复` = 上游未解决；`已修复(可移除)` = 上游已修复，可移除本地补丁；`不适用` = 需求定制类改动，不期望上游修复

---

## 基础设施文件

以下文件是本仓库新增的工作流基础设施，不属于原项目，也不是对原项目的功能修改。与上游对比时会出现在 diff 中，合并时应直接保留。

| 文件 | 用途 |
|------|------|
| `.github/workflows/upstream-sync.yml` | 定时同步上游仓库到 main 分支，有更新时发飞书通知 |
| `.github/workflows/deploy-trigger.yml` | nsfe 分支有推送时调用部署 Webhook |
| `auto-deploy.sh` | 服务器端自动部署脚本（支持 Docker 变更检测与自动重建） |
| `MODIFICATIONS.md` | 本文件，记录所有修改 |
| `.gitignore` | 忽略部署环境特有的文件 |
| `config/database.php.example` | 数据库配置模板（不含真实凭证），部署时复制为 `database.php` 并填入实际配置 |
| `Dockerfile` | PHP 8.2-FPM + Nginx 容器镜像定义 |
| `docker-compose.yml.example` | Docker 容器编排模板（不含环境特有配置），部署时复制为 `docker-compose.yml` 并按需修改容器名、端口等 |
| `docker/nginx.conf` | 容器内 Nginx 站点配置（伪静态 + FastCGI） |
| `docker/php.ini` | 容器内 PHP 运行参数 |
| `docker/entrypoint.sh` | 容器启动脚本，依次启动 PHP-FPM 和 Nginx |
| `README-new.md` | 部署与维护指南（Docker 部署、上游同步、代码修改流程） |

> **维护规则**：当上游更新了 `config/database.php`（如新增配置项、调整结构），需要将上游的变更同步到 `config/database.php.example` 中，保持模板与上游结构一致。

### .gitignore 说明

以下文件是部署环境特有的，不应提交到仓库：

| 文件 | 说明 |
|------|------|
| `404.html` | 宝塔面板自定义错误页 |
| `.htaccess` | Apache/宝塔生成的配置（已被 git 跟踪，通过 assume-unchanged 忽略） |
| `.user.ini` | PHP 运行时配置（宝塔面板生成） |
| `config/database.php` | 数据库配置，含真实凭证（已被 git 跟踪，通过 assume-unchanged 忽略）。模板文件为 `config/database.php.example` |
| `docker-compose.yml` | 实际运行的容器编排配置，部署环境可能修改容器名、端口等。模板文件为 `docker-compose.yml.example` |
| `runtime/` | Smarty 模板编译缓存和 WAF 序列化缓存，运行时自动生成 |
| `kernel/Install/Lock` | 安装锁文件，安装完成后自动生成 |
| `config/terms` | 用户协议同意记录，管理员首次登录时自动生成 |
| `assets/cache/` | 用户上传图片缓存，运行时由上传接口创建 |

### 本地仓库配置

以下配置仅对本地仓库生效，克隆或部署到新环境时需要重新执行：

```bash
# 忽略部署环境特有文件的本地修改（文件仍被 git 跟踪，但本地改动不会出现在 git status 中）
git update-index --assume-unchanged config/database.php
git update-index --assume-unchanged .htaccess
```

---

## 改动列表

### 1. 移除管理端会话的 IP 校验

- **类型**：bug 修复
- **文件**：`app/Interceptor/ManageSession.php`
- **描述**：原代码在每次请求时校验当前 IP 是否与登录时记录的 IP 一致（`$manage->login_ip != Client::getAddress()`），当客户端真实 IP 发生变化（动态 IP、移动网络、多出口 NAT）时会立即触发"登录会话过期，请重新登录.."。移除该 IP 校验条件，JWT 签名验证 + 过期时间 + loginTime 一致性检查已足够保证会话安全
- **上游状态**：未修复
