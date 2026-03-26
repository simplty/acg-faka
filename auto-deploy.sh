#!/bin/bash

# =============================================================================
# acg-faka 自动部署脚本
#
# 用法: ./auto-deploy.sh [选项]
#
# 选项:
#   --rebuild       强制重新构建 Docker 镜像（无论配置是否变更）
#   --force-pull    强制拉取远端代码覆盖本地所有修改（git reset --hard）
#
# 默认行为（不加参数）:
#   - 拉取远端代码，仅快进合并
#   - Dockerfile / docker/ 变更时重建镜像；docker-compose.yml.example 变更时仅重建容器
#   - 若容器未运行则自动启动
#
# 通知: 部署开始、构建、成功、失败均会发送飞书卡片通知
# =============================================================================

DEPLOY_DIR="$(cd "$(dirname "$0")" && pwd)"
BRANCH="nsfe"
LOG_FILE="$DEPLOY_DIR/deploy.log"
FEISHU_WEBHOOK="https://open.feishu.cn/open-apis/bot/v2/hook/29779784-8be9-4eac-b010-9e43348bd055"

# 解析参数
FORCE_REBUILD=false
FORCE_PULL=false
for arg in "$@"; do
  case "$arg" in
    --rebuild)    FORCE_REBUILD=true ;;
    --force-pull) FORCE_PULL=true ;;
    *) echo "未知参数: $arg"; exit 1 ;;
  esac
done

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 飞书卡片通知
# 参数: $1=标题 $2=颜色(green/red/orange/blue) $3=内容（支持多行，每行一个字段） $4=底部状态文本
notify() {
  local title="$1" color="$2" content="$3" status="$4"
  local elements=""

  # 将内容按行拆分为卡片字段
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    elements="${elements}{\"tag\":\"div\",\"text\":{\"tag\":\"lark_md\",\"content\":\"${line}\"}},"
  done <<< "$content"

  # 分隔线 + 底部状态
  if [ -n "$status" ]; then
    elements="${elements}{\"tag\":\"hr\"},{\"tag\":\"div\",\"text\":{\"tag\":\"lark_md\",\"content\":\"${status}\"}},"
  fi

  # 移除末尾逗号
  elements="${elements%,}"

  curl -s -o /dev/null -X POST "$FEISHU_WEBHOOK" \
    -H 'Content-Type: application/json' \
    -d "{
      \"msg_type\": \"interactive\",
      \"card\": {
        \"header\": {
          \"title\": {\"tag\": \"plain_text\", \"content\": \"${title}\"},
          \"template\": \"${color}\"
        },
        \"elements\": [${elements}]
      }
    }" 2>/dev/null || true
}

# 错误处理：捕获异常并发送失败通知
on_error() {
  local exit_code=$?
  local error_msg="${DEPLOY_ERROR:-未知错误 (exit code: $exit_code)}"
  log "部署失败: $error_msg"
  notify "acg-faka 部署失败" "red" \
    "**分支:** ${BRANCH}
**路径:** ${DEPLOY_DIR}
**阶段:** ${DEPLOY_STAGE:-未知}
**错误:** ${error_msg}
**时间:** $(date '+%Y-%m-%d %H:%M:%S')" \
    "部署异常终止，请检查服务器日志"
  exit $exit_code
}
trap on_error ERR

cd "$DEPLOY_DIR"
DEPLOY_STAGE="初始化"

# ---- 开始部署 ----
log "开始部署 acg-faka ($BRANCH)"
notify "acg-faka 开始部署" "blue" \
  "**分支:** ${BRANCH}
**路径:** ${DEPLOY_DIR}
**参数:** $([ "$FORCE_REBUILD" = true ] && echo '--rebuild ')$([ "$FORCE_PULL" = true ] && echo '--force-pull')$([ "$FORCE_REBUILD" = false ] && [ "$FORCE_PULL" = false ] && echo '无')
**时间:** $(date '+%Y-%m-%d %H:%M:%S')" \
  "正在拉取代码并部署..."

# ---- 拉取代码 ----
DEPLOY_STAGE="拉取代码"
git fetch origin "$BRANCH"

# 记录变更文件列表（用于后续判断）
CHANGED_FILES=$(git diff HEAD "origin/$BRANCH" --name-only 2>/dev/null || true)

if [ "$FORCE_PULL" = true ]; then
  log "强制覆盖本地代码 (--force-pull)"
  git reset --hard "origin/$BRANCH"
else
  git merge --ff-only "origin/$BRANCH" || {
    DEPLOY_ERROR="快进合并失败，本地有未提交的修改。如需强制覆盖请使用 --force-pull"
    log "$DEPLOY_ERROR"
    on_error
  }
fi

COMMIT_INFO=$(git log --oneline -1)
log "代码更新完成: $COMMIT_INFO"

# ---- Docker 镜像构建 ----
DEPLOY_STAGE="Docker 构建"
if [ "$FORCE_REBUILD" = true ]; then
  log "强制重建镜像 (--rebuild)"
  notify "acg-faka 开始构建镜像" "orange" \
    "**原因:** --rebuild 强制重建
**路径:** ${DEPLOY_DIR}
**提交:** ${COMMIT_INFO}" \
    "正在构建 Docker 镜像..."
  docker compose up -d --build
elif echo "$CHANGED_FILES" | grep -qE '^(Dockerfile|docker/)'; then
  log "检测到镜像配置变更，重新构建镜像"
  notify "acg-faka 开始构建镜像" "orange" \
    "**原因:** Dockerfile 或 docker/ 配置变更
**路径:** ${DEPLOY_DIR}
**提交:** ${COMMIT_INFO}" \
    "正在构建 Docker 镜像..."
  docker compose up -d --build
elif echo "$CHANGED_FILES" | grep -qE '^docker-compose\.yml\.example$'; then
  log "检测到 docker-compose.yml.example 变更，重建容器（不重建镜像）"
  notify "acg-faka 重建容器" "orange" \
    "**原因:** docker-compose.yml.example 变更
**路径:** ${DEPLOY_DIR}
**提交:** ${COMMIT_INFO}" \
    "正在重建容器..."
  docker compose up -d
else
  # 无 Docker 变更时，确认容器在运行
  if ! docker compose ps --status running --quiet 2>/dev/null | grep -q .; then
    log "容器未运行，启动容器"
    docker compose up -d
  fi
fi

# ---- 部署成功 ----
log "部署完成"
notify "acg-faka 部署成功" "green" \
  "**分支:** ${BRANCH}
**路径:** ${DEPLOY_DIR}
**提交:** ${COMMIT_INFO}
**时间:** $(date '+%Y-%m-%d %H:%M:%S')" \
  "部署完成，服务运行中"
