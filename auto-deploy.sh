#!/bin/bash
set -e

DEPLOY_DIR="/www/wwwroot/shops/aicode"
BRANCH="nsfe"
LOG_FILE="$DEPLOY_DIR/deploy.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

cd "$DEPLOY_DIR"

log "开始部署 acg-faka ($BRANCH)"

# 拉取最新代码
git fetch origin "$BRANCH"
git reset --hard "origin/$BRANCH"

log "代码更新完成: $(git log --oneline -1)"

# 依赖变更检查：如果 composer.lock 有更新，运行 composer install
if git diff HEAD@{1} --name-only 2>/dev/null | grep -q 'composer.lock'; then
  log "检测到 composer.lock 变更，执行 composer install"
  composer install --no-dev --optimize-autoloader
fi

# 清除 OPcache（如果 PHP-FPM 在运行）
if command -v php &>/dev/null; then
  php -r 'if (function_exists("opcache_reset")) { opcache_reset(); echo "OPcache cleared\n"; }' 2>/dev/null || true
fi

log "部署完成"
