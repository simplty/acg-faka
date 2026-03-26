# 诊断报告：PHP-FPM Operation not permitted

## 环境信息

- **OS**: Linux ecsTj0g 6.8.0-59-generic #61-Ubuntu SMP PREEMPT_DYNAMIC Fri Apr 11 23:16:11 UTC 2025 x86_64
- **Docker**: 28.0.4
- **容器名**: aihub-shop
- **项目目录（宿主机）**: `/www/wwwroot/aihub/acg-faka`
- **项目目录（容器内）**: `/var/www/html`（通过 bind mount 映射）

---

## 诊断结果

### 1. docker-compose.yml 配置

```bash
$ cat /www/wwwroot/aihub/acg-faka/docker-compose.yml
```

```yaml
services:
  app:
    container_name: aihub-shop
    security_opt:
      - apparmor:unconfined
    build: .
    ports:
      - "3080:80"
    volumes:
      - .:/var/www/html
    extra_hosts:
      - "host.docker.internal:host-gateway"
    restart: unless-stopped
```

**结论**: `security_opt` 已正确写入。

### 2. 容器实际运行时安全选项

```bash
$ docker inspect aihub-shop --format '{{json .HostConfig.SecurityOpt}}'
["apparmor:unconfined"]
```

**结论**: 容器确实以 `apparmor:unconfined` 运行。

### 3. 最新错误日志

```bash
$ docker logs aihub-shop 2>&1 | tail -10
```

```
[26-Mar-2026 01:20:42] NOTICE: fpm is running, pid 8
[26-Mar-2026 01:20:42] NOTICE: ready to handle connections
127.0.0.1 -  26/Mar/2026:01:20:52 +0000 "GET /index.php" 404
ERROR: Unable to open primary script: /var/www/html/index.php (Operation not permitted)
127.0.0.1 -  26/Mar/2026:01:20:55 +0000 "GET /index.php" 404
ERROR: Unable to open primary script: /var/www/html/index.php (Operation not permitted)
ERROR: Unable to open primary script: /var/www/html/index.php (Operation not permitted)
127.0.0.1 -  26/Mar/2026:01:23:02 +0000 "HEAD /index.php" 404
127.0.0.1 -  26/Mar/2026:01:23:33 +0000 "GET /index.php" 404
ERROR: Unable to open primary script: /var/www/html/index.php (Operation not permitted)
```

**结论**: 每次 HTTP 请求均触发 "Operation not permitted" 错误。

### 4. 容器运行用户

```bash
$ docker exec aihub-shop id
uid=0(root) gid=0(root) groups=0(root)
```

**结论**: 容器主进程以 root 运行。

### 5. 文件存在性与权限

```bash
$ docker exec aihub-shop ls -la /var/www/html/index.php
-rw-r--r-- 1 root root 105 Mar 26 00:38 /var/www/html/index.php
```

**结论**: 文件存在，权限 644，所有者 root:root，所有用户可读。

### 6. PHP CLI 执行测试（root）

```bash
$ docker exec aihub-shop php /var/www/html/index.php
```

**结果**: ✅ 成功 — 输出了应用的 404 页面 HTML（应用正常路由）。

### 7. PHP file_exists 测试

```bash
$ docker exec aihub-shop php -r "var_dump(file_exists('/var/www/html/index.php'));"
bool(true)
```

**结论**: PHP CLI 能正常看到文件。

### 8. www-data 用户 CLI 执行测试

```bash
$ docker exec aihub-shop su -s /bin/sh www-data -c 'php /var/www/html/index.php'
```

**结果**: ✅ 成功 — 同样输出了应用的 404 页面 HTML。

### 9. HTTP 访问测试

```bash
$ curl -I http://127.0.0.1:3080/
HTTP/1.1 404 Not Found
Server: nginx
X-Powered-By: PHP/8.2.30

$ curl -s http://127.0.0.1:3080/
No input file specified.
```

**结论**: Nginx 正常转发，但 PHP-FPM 无法打开脚本文件，返回 "No input file specified"。
（注：HEAD 请求偶尔返回了缓存的 PHP 响应头，但 GET 请求始终失败。）

### 10. AppArmor 状态（宿主机）

```bash
$ aa-status 2>/dev/null | grep -A5 docker
```

**结果**: 多数容器使用 `docker-default` 配置文件，但 aihub-shop 未在列表中（因为已设为 unconfined）。

### 11. 宿主机 AppArmor 状态

```bash
$ cat /proc/1/attr/current
unconfined
```

### 12. 容器内 AppArmor 状态

```bash
$ docker exec aihub-shop cat /proc/1/attr/current
unconfined
```

**结论**: 容器 AppArmor 已正确关闭，**不是问题根因**。

### 13. SELinux 状态

```bash
$ getenforce 2>/dev/null || echo "SELinux not installed"
SELinux not installed
```

**结论**: SELinux 未安装，排除。

### 14. 文件安全上下文

```bash
$ ls -laZ /www/wwwroot/aihub/acg-faka/index.php
-rw-r--r-- 1 root root ? 105 Mar 26 08:38 /www/wwwroot/aihub/acg-faka/index.php
```

**结论**: 无 SELinux 上下文标签（`?`），正常。

### 15. 挂载点信息

```bash
$ mount | grep "/www/wwwroot"
```

**结果**: 无输出 — `/www/wwwroot` 不是独立挂载点，继承根分区属性，无 `noexec` 限制。

### 16. Docker 安全配置

```bash
$ docker info 2>/dev/null | grep -i -E "security|apparmor|seccomp|selinux"
Security Options:
  apparmor
  seccomp
```

**结论**: Docker 使用 AppArmor + Seccomp，但该容器已豁免 AppArmor。

---

## 额外发现：关键线索 🔑

### PHP-FPM Worker 配置

```bash
$ docker exec aihub-shop cat /usr/local/etc/php-fpm.d/www.conf | grep -E "^user|^group|^listen"
user = www-data
group = www-data
listen = 127.0.0.1:9000
```

### `.user.ini` 文件内容（根因所在！）

```bash
$ cat /www/wwwroot/aihub/acg-faka/.user.ini
open_basedir=/www/wwwroot/aihub/acg-faka/:/tmp/
```

### PHP-FPM 的 user_ini 配置

```bash
$ docker exec aihub-shop php-fpm -i | grep -E "user_ini|open_basedir"
open_basedir => no value => no value        # 主进程配置无 open_basedir
user_ini.cache_ttl => 300 => 300            # .user.ini 缓存 5 分钟
user_ini.filename => .user.ini => .user.ini # PHP-FPM 会读取 .user.ini
```

### Nginx Server 配置

```nginx
server {
    listen 80;
    server_name _;
    root /var/www/html;
    index index.php;

    location ~ \.php$ {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
}
```

---

## 结论：根因分析

### 根因：`.user.ini` 中的 `open_basedir` 路径与容器内路径不匹配

**完整因果链**：

1. 项目根目录有 `.user.ini` 文件，内容为：
   ```
   open_basedir=/www/wwwroot/aihub/acg-faka/:/tmp/
   ```

2. `docker-compose.yml` 通过 bind mount 将宿主机 `/www/wwwroot/aihub/acg-faka` 映射到容器的 `/var/www/html`

3. PHP-FPM 收到请求后，从 document root（`/var/www/html/`）读取 `.user.ini`，将 `open_basedir` 设为 `/www/wwwroot/aihub/acg-faka/:/tmp/`

4. PHP-FPM 尝试打开 `/var/www/html/index.php`，但该路径**不在** open_basedir 允许的路径列表中（容器内根本不存在 `/www/wwwroot/` 路径）

5. 结果：返回 EPERM → `"Unable to open primary script: /var/www/html/index.php (Operation not permitted)"`

**为什么 PHP CLI 正常但 PHP-FPM 不正常**：
- PHP CLI 不读取 `.user.ini`（仅 CGI/FastCGI SAPI 才会读取）
- 因此 `php -i | grep open_basedir` 显示 `no value`，CLI 测试全部通过

**为什么 AppArmor unconfined 没有解决问题**：
- 问题根本不是 AppArmor/SELinux 等系统级安全策略
- 是 PHP 自身的 `open_basedir` 安全机制导致的，在应用层面拒绝了文件访问

---

## 解决方案

### 方案 A：修改 `.user.ini` 使用容器内路径（推荐）

```ini
open_basedir=/var/www/html/:/tmp/
```

> ⚠️ 修改后需等待最多 5 分钟（`user_ini.cache_ttl=300`）生效，或重启 PHP-FPM：
> ```bash
> docker exec aihub-shop kill -USR2 1
> ```

### 方案 B：删除 `.user.ini` 中的 open_basedir

如果容器环境已经提供了足够的隔离（Docker 本身就是沙箱），可以移除 open_basedir 限制：

```bash
# 清空 .user.ini 或删除 open_basedir 行
echo "" > /www/wwwroot/aihub/acg-faka/.user.ini
```

### 方案 C：在 `.dockerignore` 中排除 `.user.ini`

防止宿主机的 `.user.ini` 被挂载到容器内：

```
# .dockerignore
.user.ini
```

> ⚠️ 注意：bind mount (`volumes: - .:/var/www/html`) 不受 `.dockerignore` 影响，`.dockerignore` 仅影响 `COPY`/`ADD`。此方案需要改用 Docker volume 或在 Dockerfile 中显式删除该文件。

### 方案 D（适用于 bind mount）：在 Dockerfile 或启动脚本中覆盖

在容器启动时覆盖 `.user.ini`：

```dockerfile
# Dockerfile 中添加
RUN echo "open_basedir=/var/www/html/:/tmp/" > /var/www/html/.user.ini
```

或在 `docker-compose.yml` 中：
```yaml
command: sh -c "echo 'open_basedir=/var/www/html/:/tmp/' > /var/www/html/.user.ini && exec supervisord ..."
```

---

## 推荐操作

**最快修复**（方案 A）：
```bash
# 修改 .user.ini
echo "open_basedir=/var/www/html/:/tmp/" > /www/wwwroot/aihub/acg-faka/.user.ini

# 重启 PHP-FPM 使其立即生效
docker exec aihub-shop kill -USR2 1

# 验证
curl -s http://127.0.0.1:3080/
```

**长期方案**：考虑 `.user.ini` 是否是宝塔面板等宿主机管理工具自动生成的。如果是，需要在宝塔中关闭该站点的 open_basedir 设置，或在部署脚本中加入覆盖逻辑，防止每次部署后被恢复。
