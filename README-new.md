# acg-faka 部署与维护指南

本仓库是 [acg-faka](https://github.com/lizhipay/acg-faka) 的定制 fork，通过 `nsfe` 分支维护本地修改，同时自动跟踪上游更新。

## 分支策略

| 分支 | 用途 |
|------|------|
| `main` | 与上游保持同步，由 GitHub Actions 每日自动拉取 |
| `nsfe` | 修改分支，所有定制改动在此进行，推送后自动触发部署 |

```
上游 (lizhipay/acg-faka)
  │
  ▼  (每日自动同步)
main ──────────────────────────
  │
  ▼  (手动合并 + 冲突解决)
nsfe ──────────────────────────
  │
  ▼  (推送后自动触发)
服务器部署
```

## 日常开发：修改代码

### 1. 在 nsfe 分支上开发

```bash
git checkout nsfe
# 进行代码修改
```

### 2. 更新 MODIFICATIONS.md

每次修改原项目代码后，**必须**在 `MODIFICATIONS.md` 中添加记录，格式如下：

```markdown
### <序号>. <简要标题>

- **类型**：bug 修复 / 需求定制
- **文件**：`path/to/file`
- **描述**：做了什么、为什么要改
- **上游状态**：未修复 / 已修复(可移除) / 不适用
```

字段说明：

- **类型**：
  - `bug 修复`：原项目的缺陷修复
  - `需求定制`：个性化功能改动
- **上游状态**：
  - `未修复`：上游尚未解决（bug 修复类默认值）
  - `已修复(可移除)`：上游已修复，可移除本地补丁
  - `不适用`：需求定制类改动，不期望上游修复

> **注意**：如果新增了基础设施文件（如新的配置文件、脚本等），也需要在 `MODIFICATIONS.md` 的「基础设施文件」表格中登记。

### 3. 提交并推送

```bash
git add .
git commit -m "描述你的改动"
git push origin nsfe
```

推送后 GitHub Actions 会自动触发服务器部署。

## 上游同步：处理上游更新

### 自动同步流程

GitHub Actions (`upstream-sync.yml`) 每日自动执行：

1. 拉取上游最新代码到 `main` 分支
2. 如果有更新，发送飞书通知

### 收到通知后的操作

```bash
# 1. 切换到 nsfe 分支
git checkout nsfe
git pull origin nsfe

# 2. 合并 main（包含上游更新）
git merge origin/main

# 3. 如果有冲突，手动解决
#    重点关注 MODIFICATIONS.md 中记录的文件

# 4. 检查并更新 MODIFICATIONS.md
#    - bug 修复类：检查上游是否已修复，若已修复则标记为「已修复(可移除)」并移除本地补丁
#    - 需求定制类：检查上游更新是否与该改动冲突，若冲突需手动合并

# 5. 提交并推送
git push origin nsfe
```

### config/database.php.example 维护

当上游更新了 `config/database.php`（如新增配置项、调整结构），需要将上游的变更同步到 `config/database.php.example` 中，保持模板与上游结构一致。

## Docker 部署

使用 Docker 容器化部署，容器提供 Nginx + PHP-FPM 运行环境，源码通过 volume 挂载，MySQL 使用宿主机数据库。

### 目录结构

```
Dockerfile                    # PHP 8.2-FPM + Nginx
docker-compose.yml.example    # 容器编排模板
docker/
├── nginx.conf                # Nginx 站点配置（伪静态 + FastCGI）
├── php.ini                   # PHP 运行参数
└── entrypoint.sh             # 容器启动脚本（PHP-FPM + Nginx）
```

### 部署步骤

#### 1. 准备 docker-compose.yml

```bash
cp docker-compose.yml.example docker-compose.yml
```

按需修改容器名、端口等。`docker-compose.yml` 已加入 `.gitignore`，本地修改不会被 git 跟踪。

#### 2. 宿主机 MySQL 授权

确保 MySQL 用户允许来自 Docker 网段的连接：

```sql
GRANT ALL PRIVILEGES ON your_db.* TO 'your_user'@'%' IDENTIFIED BY 'your_password';
FLUSH PRIVILEGES;
```

#### 3. 启动容器

```bash
docker compose up -d --build
```

服务默认暴露在宿主机 **8080** 端口，可在 `docker-compose.yml` 中修改。

#### 4. 页面安装

访问站点地址，进入安装向导页面，填写数据库连接信息（host 填 `host.docker.internal`）和管理员账号，提交后自动完成数据库初始化和配置生成。

> 安装完成后如需修改数据库配置，可直接编辑 `config/database.php`，重启容器生效。

#### 5. 反向代理

在宝塔面板或 Nginx 中配置反向代理，将域名指向 `127.0.0.1:8080`。

## 日常维护

### 更新代码

源码通过 volume 挂载，直接 `git pull` 即可生效，无需重建容器。自动部署脚本 `auto-deploy.sh` 会处理这一切。

### 重建镜像 / 重建容器

| 变更文件 | 需要的操作 | 命令 |
|----------|-----------|------|
| `Dockerfile`、`docker/` | 重建镜像 | `docker compose up -d --build` |
| `docker-compose.yml` | 重建容器（无需重建镜像） | `docker compose up -d` |

> 自动部署脚本会区分变更类型并自动执行对应操作，通常不需要手动操作。

### 查看日志

```bash
docker logs -f acg-faka
```

### 新环境部署后的初始化

克隆或部署到新环境时，需要执行以下配置：

```bash
# 忽略部署环境特有文件的本地修改
git update-index --assume-unchanged config/database.php
git update-index --assume-unchanged .htaccess
```
