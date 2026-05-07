#!/bin/bash
#
# mihomo-manager - Mihomo & MetaCubeXD 一键化管理工具
#
# 功能：安装、更新、卸载 Mihomo 和 MetaCubeXD
# 作者：mihomo-v2.5 pro AI自动生成
# 版本：1.1.0
#

# ==================== 颜色定义 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ==================== 配置变量 ====================
MIHOMO_DIR="/etc/mihomo"
MIHOMO_BIN="/usr/local/bin/mihomo"
MIHOMO_SERVICE="/etc/systemd/system/mihomo.service"
BACKUP_DIR="/tmp/mihomo-backup-$(date +%Y%m%d%H%M%S)"
VERSION_CACHE_FILE="/tmp/mihomo-manager-cache.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MERGE_CONFIG_FILE="$SCRIPT_DIR/../conf/merge.yaml"

# GitHub 镜像加速
GITHUB_PROXY="https://gh-proxy.com"
MIHOMO_REPO="MetaCubeX/mihomo"
METACUBEXD_REPO="MetaCubeX/metacubexd"

# 代理设置
PROXY_HOST="127.0.0.1"
PROXY_PORT=""
USE_PROXY="false"

# 缓存时间（秒）
CACHE_TTL=3600  # 1小时

# ==================== 工具函数 ====================

# 打印信息
info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

# 打印警告
warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

# 打印错误
error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# 打印调试信息
debug() {
    if [ "$VERBOSE" = "true" ]; then
        echo -e "${CYAN}[DEBUG]${NC} $*"
    fi
}

# 打印步骤
step() {
    echo -e "${BLUE}[STEP]${NC} $*"
}

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "请使用 root 或 sudo 运行此脚本"
        exit 1
    fi
}

# 检查系统环境
check_system() {
    # 检查操作系统
    if [ ! -f /etc/os-release ]; then
        error "无法检测操作系统"
        exit 1
    fi
    
    . /etc/os-release
    if [ "$ID" != "ubuntu" ]; then
        warn "当前系统为 $ID，本脚本针对 Ubuntu 优化，其他系统可能不兼容"
    fi
    
    # 检查架构
    local arch=$(uname -m)
    if [ "$arch" != "x86_64" ]; then
        error "当前架构为 $arch，本脚本仅支持 amd64 (x86_64)"
        exit 1
    fi
    
    debug "系统检查通过: $PRETTY_NAME ($arch)"
}

# 检测本地代理
detect_local_proxy() {
    # 如果已经通过 --proxy 参数设置了代理，跳过检测
    if [ "$USE_PROXY" = "true" ]; then
        debug "已通过参数设置代理，跳过自动检测"
        return 0
    fi
    
    debug "检测本地代理..."
    
    # 检查 Mihomo 是否安装
    if [ ! -f "$MIHOMO_BIN" ]; then
        debug "Mihomo 未安装，跳过代理检测"
        return 0
    fi
    
    # 检查 Mihomo 服务是否运行
    if ! systemctl is-active --quiet mihomo 2>/dev/null; then
        debug "Mihomo 服务未运行，跳过代理检测"
        return 0
    fi
    
    # 从 config.yaml 读取代理端口
    if [ -f "$MIHOMO_DIR/config.yaml" ]; then
        # 首先尝试 mixed-port
        local mixed_port=$(grep -E "^mixed-port:" "$MIHOMO_DIR/config.yaml" | grep -oE '[0-9]+' | head -1)
        if [ -n "$mixed_port" ]; then
            PROXY_PORT="$mixed_port"
            debug "从配置文件读取 mixed-port: $mixed_port"
        fi
        
        # 如果没有 mixed-port，尝试 socks-port
        if [ -z "$PROXY_PORT" ]; then
            local socks_port=$(grep -E "^socks-port:" "$MIHOMO_DIR/config.yaml" | grep -oE '[0-9]+' | head -1)
            if [ -n "$socks_port" ]; then
                PROXY_PORT="$socks_port"
                debug "从配置文件读取 socks-port: $socks_port"
            fi
        fi
        
        # 如果没有 socks-port，尝试 port
        if [ -z "$PROXY_PORT" ]; then
            local port=$(grep -E "^port:" "$MIHOMO_DIR/config.yaml" | grep -oE '[0-9]+' | head -1)
            if [ -n "$port" ]; then
                PROXY_PORT="$port"
                debug "从配置文件读取 port: $port"
            fi
        fi
    fi
    
    # 默认端口
    if [ -z "$PROXY_PORT" ]; then
        PROXY_PORT="7890"
    fi
    
    # 测试代理是否可用
    local proxy_url="http://${PROXY_HOST}:${PROXY_PORT}"
    if curl -x "$proxy_url" -sL --connect-timeout 5 "http://www.gstatic.com/generate_204" > /dev/null 2>&1; then
        USE_PROXY="true"
        debug "代理可用: $proxy_url"
    else
        # 尝试 SOCKS5 代理
        proxy_url="socks5://${PROXY_HOST}:${PROXY_PORT}"
        if curl -x "$proxy_url" -sL --connect-timeout 5 "http://www.gstatic.com/generate_204" > /dev/null 2>&1; then
            USE_PROXY="true"
            debug "代理可用: $proxy_url"
        else
            USE_PROXY="false"
            debug "代理不可用"
        fi
    fi
}

# 设置代理（命令行参数）
set_proxy() {
    local proxy="$1"
    if [[ "$proxy" =~ ^[0-9]+$ ]]; then
        # 只提供了端口号
        PROXY_PORT="$proxy"
        PROXY_HOST="127.0.0.1"
    elif [[ "$proxy" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]; then
        # 提供了 host:port
        PROXY_HOST=$(echo "$proxy" | cut -d: -f1)
        PROXY_PORT=$(echo "$proxy" | cut -d: -f2)
    else
        error "无效的代理格式: $proxy"
        echo "格式: 端口号 或 IP:端口"
        exit 1
    fi
    
    USE_PROXY="true"
    info "使用代理: http://${PROXY_HOST}:${PROXY_PORT}"
}

# 检查网络连接
check_network() {
    debug "检查网络连接..."
    
    # 如果代理可用，通过代理测试
    if [ "$USE_PROXY" = "true" ]; then
        if curl -x "http://${PROXY_HOST}:${PROXY_PORT}" -sL --connect-timeout 5 "http://www.gstatic.com/generate_204" > /dev/null 2>&1; then
            debug "网络连接正常（通过代理）"
            return 0
        fi
    fi
    
    # 直连测试
    if ping -c 1 -W 3 github.com > /dev/null 2>&1; then
        debug "网络连接正常（直连）"
        return 0
    fi
    
    if ping -c 1 -W 3 baidu.com > /dev/null 2>&1; then
        debug "网络连接正常（国内）"
        return 0
    fi
    
    error "网络连接失败，请检查网络设置或使用 --proxy 参数指定代理"
    exit 1
}

# 检查磁盘空间
check_disk_space() {
    local required_mb=500
    local available_mb=$(df -m / | awk 'NR==2 {print $4}')
    
    if [ "$available_mb" -lt "$required_mb" ]; then
        error "磁盘空间不足: 可用 ${available_mb}MB，需要至少 ${required_mb}MB"
        exit 1
    fi
    
    debug "磁盘空间检查通过: 可用 ${available_mb}MB"
}

# 获取版本缓存
get_version_cache() {
    local repo="$1"
    local cache_key=$(echo "$repo" | tr '/' '_')
    
    # 检查缓存文件是否存在
    if [ -f "$VERSION_CACHE_FILE" ]; then
        local cache_time=$(cat "$VERSION_CACHE_FILE" | grep -o "\"${cache_key}_time\":[0-9]*" | grep -oE '[0-9]+' || echo "0")
        local current_time=$(date +%s)
        local age=$((current_time - cache_time))
        
        # 检查缓存是否过期
        if [ "$age" -lt "$CACHE_TTL" ]; then
            local version=$(cat "$VERSION_CACHE_FILE" | grep -o "\"${cache_key}\":\"[^\"]*\"" | grep -oE '"[^"]*"$' | tr -d '"' || echo "")
            if [ -n "$version" ] && echo "$version" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
                debug "从缓存获取版本: $version (缓存时间: ${age}秒前)"
                echo "$version"
                return 0
            fi
        fi
    fi
    
    return 1
}

# 保存版本缓存
save_version_cache() {
    local repo="$1"
    local version="$2"
    local cache_key=$(echo "$repo" | tr '/' '_')
    local current_time=$(date +%s)
    
    # 读取现有缓存或创建新的
    local cache_content="{}"
    if [ -f "$VERSION_CACHE_FILE" ]; then
        cache_content=$(cat "$VERSION_CACHE_FILE")
    fi
    
    # 更新缓存（简单的 JSON 操作）
    # 移除旧的条目
    cache_content=$(echo "$cache_content" | sed -E "s/\"${cache_key}\":\"[^\"]*\",?//g; s/\"${cache_key}_time\":[0-9]*,?//g")
    cache_content=$(echo "$cache_content" | sed 's/,\}/}/g; s/{,/{/g')
    
    # 添加新的条目
    if [ "$cache_content" = "{}" ]; then
        cache_content="{\"${cache_key}\":\"${version}\",\"${cache_key}_time\":${current_time}}"
    else
        cache_content=$(echo "$cache_content" | sed "s/}/,\"${cache_key}\":\"${version}\",\"${cache_key}_time\":${current_time}}/")
    fi
    
    echo "$cache_content" > "$VERSION_CACHE_FILE"
    debug "缓存已更新: $repo = $version"
}

# 获取最新版本号
get_latest_version() {
    local repo="$1"
    local version=""
    
    debug "获取 $repo 最新版本..."
    
    # 首先检查缓存
    version=$(get_version_cache "$repo" 2>/dev/null || echo "")
    if [ -n "$version" ]; then
        echo "$version"
        return 0
    fi
    
    # 尝试多种方式获取版本
    
    # 1. 从 GitHub API 获取（最可靠）
    debug "尝试从 GitHub API 获取版本..."
    local api_url="https://api.github.com/repos/$repo/releases/latest"
    version=$(curl -sL --connect-timeout 10 "$api_url" 2>/dev/null | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    
    # 2. 如果 API 失败，尝试使用代理访问 API
    if [ -z "$version" ] && [ "$USE_PROXY" = "true" ]; then
        debug "API 失败，尝试使用代理访问 API..."
        version=$(curl -x "http://${PROXY_HOST}:${PROXY_PORT}" -sL --connect-timeout 10 "$api_url" 2>/dev/null | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        
        if [ -z "$version" ]; then
            version=$(curl -x "socks5://${PROXY_HOST}:${PROXY_PORT}" -sL --connect-timeout 10 "$api_url" 2>/dev/null | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        fi
    fi
    
    # 3. 如果还是失败，尝试直连 GitHub 网页
    if [ -z "$version" ]; then
        debug "API 失败，尝试直连 GitHub 网页..."
        version=$(curl -sL --connect-timeout 10 "https://github.com/$repo/releases/latest" 2>/dev/null | grep -oE 'tag/v[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/tag\///')
    fi
    
    # 4. 如果直连失败，尝试使用代理访问网页
    if [ -z "$version" ] && [ "$USE_PROXY" = "true" ]; then
        debug "直连失败，尝试使用代理访问网页..."
        version=$(curl -x "http://${PROXY_HOST}:${PROXY_PORT}" -sL --connect-timeout 10 "https://github.com/$repo/releases/latest" 2>/dev/null | grep -oE 'tag/v[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/tag\///')
    fi
    
    if [ -z "$version" ]; then
        error "无法获取 $repo 最新版本，请检查网络连接或使用 --proxy 参数"
        return 1
    fi
    
    # 验证版本格式
    if ! echo "$version" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
        error "获取到无效版本号: $version"
        return 1
    fi
    
    # 保存缓存
    save_version_cache "$repo" "$version"
    
    echo "$version"
}

# 下载文件（带重试）
download_file() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        debug "下载 $url (尝试 $((retry+1))/$max_retries)..."
        
        # 尝试直连下载
        if curl -sL --connect-timeout 30 -o "$output" "$url" 2>/dev/null; then
            if [ -f "$output" ] && [ -s "$output" ]; then
                debug "下载成功（直连）: $output"
                return 0
            fi
        fi
        
        # 如果直连失败，尝试使用代理
        if [ "$USE_PROXY" = "true" ]; then
            debug "直连下载失败，尝试使用代理..."
            
            # 尝试 HTTP 代理
            if curl -x "http://${PROXY_HOST}:${PROXY_PORT}" -sL --connect-timeout 30 -o "$output" "$url" 2>/dev/null; then
                if [ -f "$output" ] && [ -s "$output" ]; then
                    debug "下载成功（HTTP 代理）: $output"
                    return 0
                fi
            fi
            
            # 尝试 SOCKS5 代理
            if curl -x "socks5://${PROXY_HOST}:${PROXY_PORT}" -sL --connect-timeout 30 -o "$output" "$url" 2>/dev/null; then
                if [ -f "$output" ] && [ -s "$output" ]; then
                    debug "下载成功（SOCKS5 代理）: $output"
                    return 0
                fi
            fi
        fi
        
        retry=$((retry+1))
        warn "下载失败，重试中..."
        sleep 2
    done
    
    error "下载失败: $url"
    return 1
}

# 检测当前代理端口
detect_proxy_port() {
    local port=""
    
    # 从 config.yaml 读取
    if [ -f "$MIHOMO_DIR/config.yaml" ]; then
        port=$(grep -E "^external-controller:" "$MIHOMO_DIR/config.yaml" | grep -oE '[0-9]+' | tail -1)
    fi
    
    # 默认端口
    if [ -z "$port" ]; then
        port="9090"
    fi
    
    echo "$port"
}

# 检查代理是否可用
check_proxy() {
    local port=$(detect_proxy_port)
    local proxy_url="http://127.0.0.1:$port"
    
    debug "检查代理: $proxy_url"
    
    # 检查代理服务是否运行
    if systemctl is-active --quiet mihomo 2>/dev/null; then
        # 测试代理是否可用
        if curl -x "$proxy_url" -sL --connect-timeout 5 "http://www.gstatic.com/generate_204" > /dev/null 2>&1; then
            PROXY_PORT="$port"
            USE_PROXY="true"
            debug "代理可用: $proxy_url"
            return 0
        fi
    fi
    
    debug "代理不可用，将使用直连"
    USE_PROXY="false"
    return 1
}

# 备份配置文件
backup_config() {
    if [ -d "$MIHOMO_DIR" ]; then
        info "备份配置文件到 $BACKUP_DIR..."
        mkdir -p "$BACKUP_DIR"
        cp -r "$MIHOMO_DIR" "$BACKUP_DIR/" 2>/dev/null || true
        debug "配置备份完成"
    fi
}

# 获取 MetaCubeXD 版本
get_ui_version() {
    # 首先尝试从 version 文件读取
    if [ -f "$MIHOMO_DIR/ui/version" ]; then
        cat "$MIHOMO_DIR/ui/version" 2>/dev/null
        return
    fi
    
    # 如果失败，从 index.html 中提取 appVersion
    if [ -f "$MIHOMO_DIR/ui/index.html" ]; then
        local version=$(grep -oE 'appVersion[":]+[0-9]+\.[0-9]+\.[0-9]+' "$MIHOMO_DIR/ui/index.html" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [ -n "$version" ]; then
            echo "v$version"
            return
        fi
    fi
    
    # 如果都失败，返回未安装
    echo "未安装"
}

# 服务管理函数
service_install() {
    debug "创建 systemd 服务..."
    cat > "$MIHOMO_SERVICE" << 'EOF'
[Unit]
Description=mihomo Daemon, Another Clash Kernel.
After=network.target NetworkManager.service systemd-networkd.service iwd.service

[Service]
Type=simple
LimitNPROC=500
LimitNOFILE=1000000
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
Restart=always
ExecStartPre=/usr/bin/sleep 1s
ExecStart=/usr/local/bin/mihomo -d /etc/mihomo
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    debug "systemd 服务创建完成"
}

service_start() {
    debug "启动 Mihomo 服务..."
    systemctl enable mihomo 2>/dev/null || true
    systemctl start mihomo

    # 等待服务稳定（mihomo 启动时需下载 GeoIP 等资源）
    local wait_count=0
    local max_wait=30
    while [ $wait_count -lt $max_wait ]; do
        sleep 1
        wait_count=$((wait_count+1))
        if ! systemctl is-active --quiet mihomo; then
            error "Mihomo 服务启动失败"
            journalctl -u mihomo --no-pager -n 10 --no-hostname
            return 1
        fi
        if ss -tlnp 2>/dev/null | grep -q ":9090 "; then
            info "Mihomo 服务启动成功"
            return 0
        fi
    done

    if systemctl is-active --quiet mihomo; then
        warn "Mihomo 服务启动超时，但进程仍在运行，请手动检查"
        return 0
    fi

    error "Mihomo 服务启动失败"
    journalctl -u mihomo --no-pager -n 10 --no-hostname
    return 1
}

service_stop() {
    debug "停止 Mihomo 服务..."
    systemctl stop mihomo 2>/dev/null || true
    systemctl disable mihomo 2>/dev/null || true
    debug "Mihomo 服务已停止"
}

# 验证配置文件
verify_config() {
    if [ -f "$MIHOMO_DIR/config.yaml" ]; then
        debug "验证配置文件..."
        local output
        local exit_code

        # 使用 timeout 防止 mihomo -t 因网络问题卡住（GeoIP 下载等）
        output=$(timeout 30 $MIHOMO_BIN -d "$MIHOMO_DIR" -t 2>&1)
        exit_code=$?

        # timeout 退出码 124 表示超时
        if [ $exit_code -eq 124 ]; then
            warn "配置验证超时（可能因 GeoIP 下载），跳过验证"
            return 0
        fi

        if [ $exit_code -eq 0 ]; then
            debug "配置文件验证通过"
            return 0
        fi

        # 检查是否只是 geoip.metadb 下载失败（配置文件本身有效）
        if echo "$output" | grep -q "can't download MMDB\|can't initial GeoIP"; then
            if echo "$output" | grep -q "yaml:\|mapping key\|unmarshal"; then
                warn "配置文件 YAML 格式错误"
                return 1
            else
                debug "配置文件验证通过（geoip.metadb 下载失败，不影响配置有效性）"
                return 0
            fi
        fi

        # 其他错误
        warn "配置文件验证失败"
        return 1
    fi
    return 1
}

# 显示安装摘要
show_install_summary() {
    local mihomo_version=$($MIHOMO_BIN -v 2>/dev/null || echo "未知")
    local ui_version=$(get_ui_version)
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  安装完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "  Mihomo 版本:     ${CYAN}$mihomo_version${NC}"
    echo -e "  MetaCubeXD 版本: ${CYAN}$ui_version${NC}"
    echo ""
    echo -e "  配置文件:        ${YELLOW}$MIHOMO_DIR/config.yaml${NC}"
    echo -e "  面板地址:        ${YELLOW}http://$(hostname -I | awk '{print $1}'):9090/ui/${NC}"
    echo -e "  面板密码:        ${YELLOW}mihomo2024${NC} (请尽快修改)"
    echo ""
    echo -e "  测试命令:"
    echo -e "    直连测试: ${CYAN}curl cip.cc${NC}"
    echo -e "    代理测试: ${CYAN}curl ifconfig.me${NC}"
    echo ""
    echo -e "${GREEN}========================================${NC}"
}

# ==================== 命令实现 ====================

# 安装命令
cmd_install() {
    local input="$1"
    
    if [ -z "$input" ]; then
        error "请指定订阅链接或配置文件路径"
        echo "用法: mihomo-manager --install -i <url|file.yaml>"
        exit 1
    fi
    
    check_root
    check_system
    check_network
    check_disk_space
    
    info "开始安装 Mihomo 和 MetaCubeXD..."
    
    # 记录安装前的状态，用于回滚
    local old_mihomo_bin=""
    local old_mihomo_dir=""
    local old_service_file=""
    
    if [ -f "$MIHOMO_BIN" ]; then
        old_mihomo_bin="$MIHOMO_BIN"
    fi
    if [ -d "$MIHOMO_DIR" ]; then
        old_mihomo_dir="$MIHOMO_DIR"
    fi
    if [ -f "$MIHOMO_SERVICE" ]; then
        old_service_file="$MIHOMO_SERVICE"
    fi
    
    # 设置错误回滚
    local install_failed=false
    rollback() {
        if [ "$install_failed" = "true" ]; then
            warn "安装失败，正在回滚..."
            
            # 停止服务
            systemctl stop mihomo 2>/dev/null || true
            systemctl disable mihomo 2>/dev/null || true
            
            # 删除新安装的文件
            rm -f "$MIHOMO_SERVICE"
            rm -f "$MIHOMO_BIN"
            rm -rf "$MIHOMO_DIR"
            
            # 恢复旧文件（如果有备份）
            if [ -n "$old_service_file" ] && [ -f "${old_service_file}.bak" ]; then
                mv "${old_service_file}.bak" "$old_service_file"
            fi
            if [ -n "$old_mihomo_bin" ] && [ -f "${old_mihomo_bin}.bak" ]; then
                mv "${old_mihomo_bin}.bak" "$MIHOMO_BIN"
            fi
            if [ -n "$old_mihomo_dir" ] && [ -d "${old_mihomo_dir}.bak" ]; then
                rm -rf "$MIHOMO_DIR"
                mv "${old_mihomo_dir}.bak" "$MIHOMO_DIR"
            fi
            
            # 重载 systemd
            systemctl daemon-reload
            
            error "安装已回滚，请检查错误并重试"
        fi
        return 0
    }
    trap rollback EXIT
    
    # 1. 获取最新版本
    step "[1/8] 获取最新版本信息..."
    local mihomo_version=$(get_latest_version "$MIHOMO_REPO")
    local metacubexd_version=$(get_latest_version "$METACUBEXD_REPO")

    if [ -z "$mihomo_version" ] || [ -z "$metacubexd_version" ]; then
        error "获取版本信息失败"
        install_failed=true
        rollback
        return 1
    fi

    # 检查当前已安装版本
    local current_mihomo=""
    local current_ui=""
    if [ -f "$MIHOMO_BIN" ]; then
        current_mihomo=$($MIHOMO_BIN -v 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "")
    fi
    current_ui=$(get_ui_version)
    [ "$current_ui" = "未安装" ] && current_ui=""

    local need_mihomo=true
    local need_ui=true

    if [ -n "$current_mihomo" ] && [ "$current_mihomo" = "$mihomo_version" ]; then
        need_mihomo=false
        info "Mihomo 已是最新版本: $current_mihomo，跳过下载"
    else
        if [ -n "$current_mihomo" ]; then
            info "Mihomo 需要更新: $current_mihomo -> $mihomo_version"
        else
            info "Mihomo 最新版本: $mihomo_version"
        fi
    fi

    if [ -n "$current_ui" ] && [ "$current_ui" = "$metacubexd_version" ]; then
        need_ui=false
        info "MetaCubeXD 已是最新版本: $current_ui，跳过下载"
    else
        if [ -n "$current_ui" ]; then
            info "MetaCubeXD 需要更新: $current_ui -> $metacubexd_version"
        else
            info "MetaCubeXD 最新版本: $metacubexd_version"
        fi
    fi

    # 如果两个组件都已是最新，且配置文件已存在，则无需操作
    if [ "$need_mihomo" = "false" ] && [ "$need_ui" = "false" ] && [ -f "$MIHOMO_DIR/config.yaml" ]; then
        # 清除 trap
        trap - EXIT
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}  所有组件已是最新版本，无需安装${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo -e "  Mihomo:     ${CYAN}$current_mihomo${NC}"
        echo -e "  MetaCubeXD: ${CYAN}$current_ui${NC}"
        echo ""
        echo -e "${GREEN}========================================${NC}"
        return 0
    fi

    # 确认需要更新，开始备份
    backup_config

    # 备份旧文件
    if [ -f "$MIHOMO_BIN" ]; then
        cp "$MIHOMO_BIN" "${MIHOMO_BIN}.bak"
    fi
    if [ -d "$MIHOMO_DIR" ]; then
        cp -r "$MIHOMO_DIR" "${MIHOMO_DIR}.bak"
    fi
    if [ -f "$MIHOMO_SERVICE" ]; then
        cp "$MIHOMO_SERVICE" "${MIHOMO_SERVICE}.bak"
    fi

    # ==================== 阶段一：下载所有资源 ====================

    # 2. 下载 Mihomo（按需）
    local mihomo_tmp="/tmp/mihomo.gz"
    if [ "$need_mihomo" = "true" ]; then
        step "[2/8] 下载 Mihomo $mihomo_version..."
        local mihomo_url="${GITHUB_PROXY}/https://github.com/${MIHOMO_REPO}/releases/download/${mihomo_version}/mihomo-linux-amd64-${mihomo_version}.gz"
        if ! download_file "$mihomo_url" "$mihomo_tmp"; then
            error "下载 Mihomo 失败"
            install_failed=true
            rollback
            return 1
        fi
    else
        step "[2/8] 下载 Mihomo... 跳过（已是最新）"
    fi

    # 3. 下载 MetaCubeXD（按需）
    local ui_tmp="/tmp/ui.tgz"
    if [ "$need_ui" = "true" ]; then
        step "[3/8] 下载 MetaCubeXD $metacubexd_version..."
        local ui_url="${GITHUB_PROXY}/https://github.com/${METACUBEXD_REPO}/releases/download/${metacubexd_version}/compressed-dist.tgz"
        if ! download_file "$ui_url" "$ui_tmp"; then
            error "下载 MetaCubeXD 失败"
            install_failed=true
            rollback
            return 1
        fi
    else
        step "[3/8] 下载 MetaCubeXD... 跳过（已是最新）"
    fi

    # 4. 下载用户订阅配置（如果是 URL）
    local user_tmp="/tmp/mihomo-user-$$.yaml"
    local input_is_url=false
    if [[ "$input" =~ ^https?:// ]]; then
        input_is_url=true
        step "[4/8] 下载订阅配置..."
        if ! download_file "$input" "$user_tmp"; then
            rm -f "$user_tmp"
            error "下载订阅配置失败"
            install_failed=true
            rollback
            return 1
        fi
    elif [ -f "$input" ]; then
        step "[4/8] 订阅配置... 使用本地文件"
        user_tmp="$input"
    else
        error "无效的输入: $input"
        install_failed=true
        rollback
        return 1
    fi

    # ==================== 阶段二：安装和配置 ====================

    # 5. 安装 Mihomo
    if [ "$need_mihomo" = "true" ]; then
        step "[5/8] 安装 Mihomo..."
        gunzip -f "$mihomo_tmp"
        mv -f "${mihomo_tmp%.gz}" "$MIHOMO_BIN"
        chmod +x "$MIHOMO_BIN"

        if ! $MIHOMO_BIN -v > /dev/null 2>&1; then
            error "Mihomo 安装失败"
            install_failed=true
            rollback
            return 1
        fi

        info "Mihomo 安装成功: $($MIHOMO_BIN -v)"
    else
        step "[5/8] 安装 Mihomo... 跳过（已是最新）"
    fi

    # 6. 合并配置文件
    step "[6/8] 配置 Mihomo..."
    mkdir -p "$MIHOMO_DIR"

    info "合并配置文件（merge.yaml 优先）..."
    if ! yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$user_tmp" "$MERGE_CONFIG_FILE" > "$MIHOMO_DIR/config.yaml"; then
        error "配置文件合并失败"
        install_failed=true
        rollback
        return 1
    fi
    [ "$input_is_url" = "true" ] && rm -f "$user_tmp"
    info "配置合并完成"

    # 验证配置文件
    if ! verify_config; then
        error "配置文件验证失败，请检查配置文件: $MIHOMO_DIR/config.yaml"
        install_failed=true
        rollback
        exit 1
    fi

    # 7. 安装 MetaCubeXD
    if [ "$need_ui" = "true" ]; then
        step "[7/8] 安装 MetaCubeXD..."
        rm -rf "$MIHOMO_DIR/ui"
        mkdir -p "$MIHOMO_DIR/ui"
        tar -xzf "$ui_tmp" -C "$MIHOMO_DIR/ui"
        rm -f "$ui_tmp"

        # 修复权限
        chown -R root:root "$MIHOMO_DIR/ui"
        chmod -R 755 "$MIHOMO_DIR/ui"

        # 保存版本信息
        echo "$metacubexd_version" > "$MIHOMO_DIR/ui/version"

        info "MetaCubeXD 安装成功"
    else
        step "[7/8] 安装 MetaCubeXD... 跳过（已是最新）"
    fi

    # 8. 创建服务并启动
    step "[8/8] 配置系统服务..."

    # 预下载 GeoIP 数据库（mihomo 启动时必需，否则会卡住或崩溃）
    if [ ! -f "$MIHOMO_DIR/geoip.metadb" ] || [ "$(stat -c%s "$MIHOMO_DIR/geoip.metadb" 2>/dev/null || echo 0)" -lt 1000000 ]; then
        info "预下载 GeoIP 数据库..."
        download_file "https://gh-proxy.com/https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb" "$MIHOMO_DIR/geoip.metadb" || warn "GeoIP 下载失败，服务启动可能较慢"
    fi

    service_install
    
    if service_start; then
        # 安装成功，清理备份文件
        rm -f "${MIHOMO_BIN}.bak"
        rm -rf "${MIHOMO_DIR}.bak"
        rm -f "${MIHOMO_SERVICE}.bak"
        rm -rf "$BACKUP_DIR"

        # 清理 mihomo 自动生成的 config.yaml.user
        rm -f "$MIHOMO_DIR/config.yaml.user"

        # 清除 trap
        trap - EXIT

        show_install_summary
    else
        error "服务启动失败，请检查日志: journalctl -u mihomo"
        install_failed=true
        rollback
        return 1
    fi
}

# 更新命令
cmd_update() {
    local target_version="$1"

    check_root

    # 检查是否已安装
    if [ ! -f "$MIHOMO_BIN" ]; then
        error "Mihomo 未安装，请先使用 --install 安装"
        exit 1
    fi

    info "开始更新 Mihomo 和 MetaCubeXD..."

    # 检测代理
    detect_local_proxy

    # 1. 获取版本信息
    step "[1/6] 获取版本信息..."

    local current_mihomo=$($MIHOMO_BIN -v 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "未知")
    local current_ui=$(get_ui_version)

    info "当前 Mihomo 版本: $current_mihomo"
    info "当前 MetaCubeXD 版本: $current_ui"

    local latest_mihomo
    local latest_metacubexd

    if [ -n "$target_version" ]; then
        latest_mihomo="$target_version"
        latest_metacubexd=$(get_latest_version "$METACUBEXD_REPO")
    else
        latest_mihomo=$(get_latest_version "$MIHOMO_REPO")
        latest_metacubexd=$(get_latest_version "$METACUBEXD_REPO")
    fi

    if [ -z "$latest_mihomo" ] || [ -z "$latest_metacubexd" ]; then
        error "获取版本信息失败"
        return 1
    fi

    info "目标 Mihomo 版本: $latest_mihomo"
    info "目标 MetaCubeXD 版本: $latest_metacubexd"

    # 2. 检查是否需要更新
    if [ "$current_mihomo" = "$latest_mihomo" ] && [ "$current_ui" = "$latest_metacubexd" ]; then
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}  已是最新版本，无需更新${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo -e "  Mihomo:     ${CYAN}$current_mihomo${NC}"
        echo -e "  MetaCubeXD: ${CYAN}$current_ui${NC}"
        echo ""
        echo -e "${GREEN}========================================${NC}"
        return 0
    fi

    # 3. 确认需要更新，开始备份
    backup_config

    local backup_dir="/tmp/mihomo-update-backup-$$"
    mkdir -p "$backup_dir"
    cp "$MIHOMO_BIN" "$backup_dir/mihomo.bak" 2>/dev/null || true
    cp -r "$MIHOMO_DIR/ui" "$backup_dir/ui.bak" 2>/dev/null || true

    # 清理函数：无论成功或失败都清理 /tmp 备份
    cleanup_tmp() {
        rm -rf "$backup_dir"
        rm -rf "$BACKUP_DIR"
    }

    # 设置错误回滚
    local update_failed=false
    rollback() {
        if [ "$update_failed" = "true" ]; then
            warn "更新失败，正在回滚..."
            systemctl stop mihomo 2>/dev/null || true
            if [ -f "$backup_dir/mihomo.bak" ]; then
                cp "$backup_dir/mihomo.bak" "$MIHOMO_BIN"
                chmod +x "$MIHOMO_BIN"
            fi
            if [ -d "$backup_dir/ui.bak" ]; then
                rm -rf "$MIHOMO_DIR/ui"
                cp -r "$backup_dir/ui.bak" "$MIHOMO_DIR/ui"
            fi
            systemctl start mihomo 2>/dev/null || true
            cleanup_tmp
            error "更新已回滚，请检查错误并重试"
        fi
        return 0
    }
    trap rollback EXIT

    # 4. 下载新版本
    step "[2/6] 下载 Mihomo $latest_mihomo..."
    local mihomo_url="${GITHUB_PROXY}/https://github.com/${MIHOMO_REPO}/releases/download/${latest_mihomo}/mihomo-linux-amd64-${latest_mihomo}.gz"
    local mihomo_tmp="/tmp/mihomo_update.gz"

    if ! download_file "$mihomo_url" "$mihomo_tmp"; then
        error "下载 Mihomo 失败"
        update_failed=true
        return 1
    fi

    step "[3/6] 下载 MetaCubeXD $latest_metacubexd..."
    local ui_url="${GITHUB_PROXY}/https://github.com/${METACUBEXD_REPO}/releases/download/${latest_metacubexd}/compressed-dist.tgz"
    local ui_tmp="/tmp/ui_update.tgz"

    if ! download_file "$ui_url" "$ui_tmp"; then
        error "下载 MetaCubeXD 失败"
        update_failed=true
        return 1
    fi

    # 5. 停止服务并更新
    step "[4/6] 停止 Mihomo 服务..."
    service_stop

    step "[5/6] 更新 Mihomo..."
    gunzip -f "$mihomo_tmp"
    mv -f "${mihomo_tmp%.gz}" "$MIHOMO_BIN"
    chmod +x "$MIHOMO_BIN"

    step "[6/6] 更新 MetaCubeXD..."
    rm -rf "$MIHOMO_DIR/ui"
    mkdir -p "$MIHOMO_DIR/ui"
    tar -xzf "$ui_tmp" -C "$MIHOMO_DIR/ui"
    rm -f "$ui_tmp"
    chown -R root:root "$MIHOMO_DIR/ui"
    chmod -R 755 "$MIHOMO_DIR/ui"
    echo "$latest_metacubexd" > "$MIHOMO_DIR/ui/version"

    # 6. 重启服务
    info "重启 Mihomo 服务..."
    if service_start; then
        cleanup_tmp
        trap - EXIT
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}  更新完成！${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo -e "  Mihomo:     ${CYAN}$current_mihomo${NC} -> ${CYAN}$latest_mihomo${NC}"
        echo -e "  MetaCubeXD: ${CYAN}$current_ui${NC} -> ${CYAN}$latest_metacubexd${NC}"
        echo ""
        echo -e "  请在浏览器按 ${YELLOW}Ctrl+F5${NC} 强制刷新面板缓存"
        echo -e "${GREEN}========================================${NC}"
    else
        error "服务启动失败，请检查日志: journalctl -u mihomo"
        update_failed=true
        return 1
    fi
}

# 卸载命令
cmd_uninstall() {
    check_root

    if [ ! -f "$MIHOMO_BIN" ] && [ ! -d "$MIHOMO_DIR" ]; then
        error "Mihomo 未安装"
        exit 1
    fi

    info "开始卸载 Mihomo..."

    # 1. 停止服务
    step "[1/5] 停止 Mihomo 服务..."
    service_stop

    # 2. 删除服务文件
    step "[2/5] 删除服务文件..."
    rm -f "$MIHOMO_SERVICE"
    systemctl daemon-reload

    # 3. 删除可执行文件
    step "[3/5] 删除可执行文件..."
    rm -f "$MIHOMO_BIN"

    # 4. 删除配置目录
    step "[4/5] 删除配置目录..."
    rm -rf "$MIHOMO_DIR"

    # 5. 清理缓存文件
    step "[5/5] 清理缓存文件..."
    rm -f "$VERSION_CACHE_FILE"

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  卸载完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "  如需重新安装，请运行:"
    echo -e "    ${CYAN}./scripts/mihomo-manager.sh --install -i <配置文件>${NC}"
    echo ""
    echo -e "${GREEN}========================================${NC}"
}

# 版本查看命令
cmd_version() {
    local mihomo_version=$($MIHOMO_BIN -v 2>/dev/null || echo "未安装")
    local ui_version=$(get_ui_version)
    local manager_version="1.1.0"
    
    echo "mihomo-manager: $manager_version"
    echo "Mihomo:         $mihomo_version"
    echo "MetaCubeXD:     $ui_version"
}

# 检查更新命令
cmd_check() {
    info "检查最新版本..."
    
    # 检测代理
    detect_local_proxy
    
    local latest_mihomo=$(get_latest_version "$MIHOMO_REPO")
    local latest_metacubexd=$(get_latest_version "$METACUBEXD_REPO")
    local current_mihomo=$($MIHOMO_BIN -v 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "未安装")
    local current_ui=$(get_ui_version)
    
    echo ""
    echo "组件            当前版本        最新版本        状态"
    echo "--------------------------------------------------------"
    
    if [ "$current_mihomo" = "未安装" ]; then
        printf "Mihomo         %-15s %-15s ${YELLOW}未安装${NC}\n" "-" "$latest_mihomo"
    elif [ "$current_mihomo" = "$latest_mihomo" ]; then
        printf "Mihomo         %-15s %-15s ${GREEN}已是最新${NC}\n" "$current_mihomo" "$latest_mihomo"
    else
        printf "Mihomo         %-15s %-15s ${CYAN}可更新${NC}\n" "$current_mihomo" "$latest_mihomo"
    fi
    
    if [ "$current_ui" = "未安装" ]; then
        printf "MetaCubeXD     %-15s %-15s ${YELLOW}未安装${NC}\n" "-" "$latest_metacubexd"
    elif [ "$current_ui" = "$latest_metacubexd" ]; then
        printf "MetaCubeXD     %-15s %-15s ${GREEN}已是最新${NC}\n" "$current_ui" "$latest_metacubexd"
    else
        printf "MetaCubeXD     %-15s %-15s ${CYAN}可更新${NC}\n" "$current_ui" "$latest_metacubexd"
    fi
    
    echo ""
    
    # 显示代理状态
    if [ "$USE_PROXY" = "true" ]; then
        echo -e "代理状态: ${GREEN}已启用${NC} (${PROXY_HOST}:${PROXY_PORT})"
    else
        echo -e "代理状态: ${YELLOW}未启用${NC}"
    fi
    echo ""
}

# 显示帮助
cmd_help() {
    echo "mihomo-manager - Mihomo & MetaCubeXD 一键化管理工具"
    echo ""
    echo "用法:"
    echo "  mihomo-manager [选项]"
    echo ""
    echo "选项:"
    echo "  --install, -i <url|file.yaml>  安装 Mihomo 和 MetaCubeXD"
    echo "                                 url: 订阅链接地址"
    echo "                                 file.yaml: 本地配置文件路径"
    echo ""
    echo "  --update, -u [-v version]      更新到最新版本或指定版本"
    echo "                                 -v: 指定版本号 (如 v1.19.22)"
    echo ""
    echo "  --uninstall                    完全卸载 Mihomo 和所有配置"
    echo ""
    echo "  --version, -V                  显示当前安装的版本信息"
    echo ""
    echo "  --check, -c                    检查是否有新版本可用"
    echo ""
    echo "  --proxy, -p <port|host:port>   指定代理地址"
    echo "                                 port: 本地代理端口"
    echo "                                 host:port: 代理地址和端口"
    echo ""
    echo "  --verbose                      显示详细执行过程"
    echo ""
    echo "  --quiet                        静默模式（只显示错误）"
    echo ""
    echo "  --help, -h                     显示此帮助信息"
    echo ""
    echo "代理说明:"
    echo "  脚本会自动检测本地 Mihomo 代理。如果自动检测失败，可以使用 --proxy 参数手动指定。"
    echo "  支持 HTTP 和 SOCKS5 代理协议。"
    echo ""
    echo "示例:"
    echo "  # 使用订阅链接安装"
    echo "  sudo mihomo-manager --install -i https://example.com/sub"
    echo ""
    echo "  # 使用本地配置文件安装"
    echo "  sudo mihomo-manager --install -i ~/config.yaml"
    echo ""
    echo "  # 使用代理更新（本地代理）"
    echo "  sudo mihomo-manager --update --proxy 7890"
    echo ""
    echo "  # 使用代理更新（指定地址）"
    echo "  sudo mihomo-manager --update --proxy 127.0.0.1:7890"
    echo ""
    echo "  # 更新到指定版本"
    echo "  sudo mihomo-manager --update -v v1.19.22"
    echo ""
    echo "  # 检查版本更新"
    echo "  mihomo-manager --check"
    echo ""
    echo "  # 使用代理检查更新"
    echo "  mihomo-manager --check --proxy 127.0.0.1:7890"
    echo ""
    echo "  # 完全卸载"
    echo "  sudo mihomo-manager --uninstall"
    echo ""
}

# ==================== 主程序 ====================

# 解析参数
VERBOSE="false"
QUIET="false"
COMMAND=""
INPUT=""
VERSION=""
PROXY_ARG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --install|-i)
            COMMAND="install"
            if [ -n "$2" ] && [[ ! "$2" =~ ^- ]]; then
                INPUT="$2"
                shift
            fi
            ;;
        --update|-u)
            COMMAND="update"
            ;;
        --uninstall)
            COMMAND="uninstall"
            ;;
        --version|-V)
            COMMAND="version"
            ;;
        --check|-c)
            COMMAND="check"
            ;;
        --proxy|-p)
            if [ -n "$2" ]; then
                PROXY_ARG="$2"
                shift
            fi
            ;;
        --verbose)
            VERBOSE="true"
            ;;
        --quiet)
            QUIET="true"
            ;;
        --help|-h)
            COMMAND="help"
            ;;
        -v)
            if [ -n "$2" ]; then
                VERSION="$2"
                shift
            fi
            ;;
        *)
            # 如果没有命令，可能是 install 的输入
            if [ -z "$COMMAND" ]; then
                error "未知选项: $1"
                cmd_help
                exit 1
            elif [ -z "$INPUT" ] && [ "$COMMAND" = "install" ]; then
                INPUT="$1"
            fi
            ;;
    esac
    shift
done

# 设置代理（如果提供了参数）
if [ -n "$PROXY_ARG" ]; then
    set_proxy "$PROXY_ARG"
fi

# 重定向输出（静默模式）
if [ "$QUIET" = "true" ]; then
    exec > /dev/null 2>&1
fi

# 执行命令
case "$COMMAND" in
    install)
        cmd_install "$INPUT"
        ;;
    update)
        cmd_update "$VERSION"
        ;;
    uninstall)
        cmd_uninstall
        ;;
    version)
        cmd_version
        ;;
    check)
        cmd_check
        ;;
    help)
        cmd_help
        ;;
    *)
        cmd_help
        exit 1
        ;;
esac

exit 0
