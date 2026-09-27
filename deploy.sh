#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/HJGSfz68/FunnyYS.git"
INSTALL_DIR="/opt/funnyys"
PORT=8008

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err() { echo -e "${RED}[x]${NC} $*" >&2; }

cleanup() { [[ -n "$SWAP_FILE" && -f "$SWAP_FILE" ]] && swapoff "$SWAP_FILE" 2>/dev/null && rm -f "$SWAP_FILE" 2>/dev/null; }
trap cleanup EXIT

show_banner() {
  echo -e "${CYAN}"
  cat << 'EOF'
  ___                   __   __  ___  ___
 | _ \ _ _  _ _  ___   / _| / _|| _ \/ __|
 |  _/| '_|| '_|/ _ \ |  _||  _||  _/\__ \
 |_|  |_|  |_|  \___/ |_|  |_|  |_|  |___/
        FunnyYS - One-Click Deployment
EOF
  echo -e "${NC}"
}

preflight() {
  log "检测系统环境 ..."
  if [[ $EUID -ne 0 ]]; then err "请以 root 用户执行"; exit 1; fi

  local mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  local mem_mb=$((mem_kb / 1024))
  if [[ $mem_mb -lt 512 ]]; then
    warn "内存仅 ${mem_mb}MB，即将创建 2GB 交换分区 ..."
    SWAP_FILE=/swapfile
    if ! grep -q "$SWAP_FILE" /proc/swaps 2>/dev/null; then
      dd if=/dev/zero of=$SWAP_FILE bs=1M count=2048 status=progress 2>/dev/null
      chmod 600 $SWAP_FILE
      mkswap $SWAP_FILE >/dev/null
      swapon $SWAP_FILE
    fi
    if ! grep -q "$SWAP_FILE" /etc/fstab 2>/dev/null; then
      echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
      log "交换分区已持久化"
    fi
    log "内存: ${mem_mb}MB + 2GB Swap"
  else
    log "内存: ${mem_mb}MB"
  fi

  local disk_kb=$(df / | tail -1 | awk '{print $4}')
  local disk_gb=$((disk_kb / 1024 / 1024))
  if [[ $disk_gb -lt 2 ]]; then err "磁盘空间不足 2GB"; exit 1; fi
  log "磁盘: ${disk_gb}GB 可用"

  if command -v docker &>/dev/null; then
    DEPLOY_MODE=docker
    log "检测到 Docker，使用 Docker 部署"
  elif command -v node &>/dev/null && [[ $(node -v | cut -d. -f1 | tr -d v) -ge 18 ]]; then
    DEPLOY_MODE=node
    log "检测到 Node.js $(node -v)，使用源码部署"
  else
    DEPLOY_MODE=auto
    warn "未检测到 Docker 或 Node.js，将安装 Docker"
  fi
}

install_docker() {
  if ! command -v docker &>/dev/null; then
    log "安装 Docker ..."; curl -fsSL https://get.docker.com | sh
  fi
  if ! command -v docker compose &>/dev/null; then
    log "安装 Docker Compose ..."
    apt-get update -qq && apt-get install -y -qq docker-compose-plugin 2>/dev/null || \
      pip3 install docker-compose 2>/dev/null || true
  fi
}

install_node() {
  if ! command -v node &>/dev/null; then
    log "安装 Node.js 22 ..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y -qq nodejs
  fi
}

clone_repo() {
  log "拉取 FunnyYS ..."
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    git -C "$INSTALL_DIR" pull --ff-only
  else
    rm -rf "$INSTALL_DIR"
    git clone --depth 1 "$REPO" "$INSTALL_DIR"
  fi
  cd "$INSTALL_DIR"
}

configure_sources() {
  local json_file="源列表_全量.json"
  if [[ -f "$json_file" ]]; then
    log "从 $json_file 读取数据源 ..."
    local sources
    sources=$(python3 -c "import json; print(json.dumps(json.load(open('$json_file'))))" 2>/dev/null) || \
      sources=$(node -e "console.log(JSON.stringify(require('./$json_file')))" 2>/dev/null)
    if [[ -n "$sources" ]]; then
      echo "DEFAULT_SOURCES=$sources" > .env
      log "已写入 $(echo "$sources" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 22) 个数据源"
    fi
  else
    log "未找到 $json_file，跳过预置数据源"
  fi
}

deploy_docker() {
  docker compose up -d --build
}

deploy_node() {
  log "安装依赖 ..."
  NODE_OPTIONS="--max-old-space-size=512" npm ci --no-audit --no-fund
  log "构建 ..."
  NODE_OPTIONS="--max-old-space-size=512" npm run build
  log "启动 FunnyYS（端口 ${PORT}）..."
  NODE_OPTIONS="--max-old-space-size=512" nohup npm start > app.log 2>&1 &
  local pid=$!
  sleep 4
  if kill -0 $pid 2>/dev/null; then
    echo "$pid" > app.pid
    log "PID: $pid"
  fi
}

verify() {
  sleep 3
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${PORT}/" 2>/dev/null || echo 000)
  if [[ "$code" == "200" ]]; then
    log "${GREEN}部署成功！${NC}"
    local pub_ip
    pub_ip=$(curl -s -4 --max-time 3 ifconfig.me 2>/dev/null || echo "服务器公网 IP")
    echo ""
    echo -e "  ${CYAN}本地访问:${NC}  http://127.0.0.1:${PORT}"
    echo -e "  ${CYAN}外网访问:${NC}  http://${pub_ip}:${PORT}"
    echo ""
    warn "外网访问不通时请在云安全组 / 防火墙放行 TCP ${PORT} 端口"
    echo ""
  else
    err "HTTP $code，检查日志：cat $INSTALL_DIR/app.log"
  fi
}

main() {
  show_banner
  preflight

  log "此脚本将在 ${INSTALL_DIR} 部署 FunnyYS"
  echo -e "${YELLOW}按回车继续或 Ctrl+C 取消 ...${NC}"; read -r

  case "$DEPLOY_MODE" in
    docker) install_docker; clone_repo; configure_sources; deploy_docker ;;
    node) install_node; clone_repo; configure_sources; deploy_node ;;
    auto) install_docker; clone_repo; configure_sources; deploy_docker ;;
  esac

  verify
  log "日志文件: ${INSTALL_DIR}/app.log"
  log "重启命令: cd ${INSTALL_DIR} && npm start"
  cleanup
}

main "$@"