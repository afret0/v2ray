#!/usr/bin/env bash
set -Eeuo pipefail

readonly XUI_IMAGE="ghcr.io/mhsanaei/3x-ui:latest"
readonly XUI_CONTAINER="3x-ui"
readonly XUI_DB_DIR="/etc/x-ui"
readonly XUI_INFO_FILE="${XUI_DB_DIR}/panel-info.txt"
readonly NODE_CONTAINER="xray-reality"
readonly NODE_CONFIG_DIR="/etc/xray"
readonly NODE_CONFIG_FILE="${NODE_CONFIG_DIR}/config.json"
readonly NODE_IMAGE="teddysun/xray"
readonly INSTALLER_NAME="onekey_xray.sh"
readonly INSTALLER_URL="https://raw.githubusercontent.com/afret0/v2ray/master/onekey_xray.sh"
readonly PANEL_PORT_MIN=20000
readonly PANEL_PORT_MAX=60000
readonly PANEL_PORT_TRIES=20
readonly PANEL_WAIT_SECONDS=30
readonly NODE_WAIT_SECONDS=15
readonly CLIENT_EMAIL="user1"
readonly FLOW="xtls-rprx-vision"
readonly FINGERPRINT="chrome"
readonly LOG_MAX_SIZE="10m"
readonly LOG_MAX_FILE="3"
readonly WARP_MTU=1280
readonly WARP_TARGET_STRATEGY="ForceIPv4v6"
readonly -a WARP_DOMAINS=('geosite:category-ai-!cn' 'geosite:netflix' 'geosite:disney')
readonly WARP_LIST_FILE="${NODE_CONFIG_DIR}/warp-domains.txt"
readonly WARP_SYNC_FILE="${NODE_CONFIG_DIR}/warp-sync.sh"
readonly WARP_SYNC_STATE_FILE="${NODE_CONFIG_DIR}/warp-sync-state"
readonly WARP_SYNC_UNIT="xray-warp-sync"
readonly WARP_SYNC_CRON_MARK="# xray warp sync"

readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[1;33m'
readonly RED=$'\033[0;31m'
readonly NC=$'\033[0m'

server_ip=""
port=""
sni=""
uuid=""
private_key=""
public_key=""
short_id=""
warp_enabled=false
warp_secret=""
warp_v4=""
warp_v6=""
warp_reserved=""
warp_peer=""
warp_endpoint=""
warp_custom_domains=""
warp_custom_count=0
fallback_enabled=false
fallback_up_after=""
fallback_up_rate=""
fallback_up_burst=""
fallback_down_after=""
fallback_down_rate=""
fallback_down_burst=""
panel_port=""
panel_user=""
panel_pass=""
panel_path=""
api_token=""
inbound_id=""
node_removed=false
tmp_installer=""

step() { printf '%s\n' "${GREEN}$*${NC}"; }
info() { printf '%s\n' "${YELLOW}$*${NC}"; }
fail() {
    printf '%s\n' "${RED}错误: $*${NC}" >&2
    exit 1
}

on_error() {
    printf '%s\n' "${RED}错误: 第 $1 行命令执行失败 (退出码 $2): $3${NC}" >&2
}

cleanup() {
    if [ -n "$tmp_installer" ]; then rm -f "$tmp_installer"; fi
}

trap '[ "$BASH_SUBSHELL" -eq 0 ] && on_error "$LINENO" "$?" "$BASH_COMMAND"' ERR
trap cleanup EXIT

valid_port() {
    [[ $1 =~ ^[0-9]{1,5}$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535))
}

valid_domain() {
    local re='^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z][A-Za-z0-9-]{0,61}[A-Za-z0-9]$'
    [ "${#1}" -le 253 ] && [[ $1 =~ $re ]]
}

valid_uuid() {
    local re='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    [[ $1 =~ $re ]]
}

valid_key() {
    [[ $1 =~ ^[A-Za-z0-9_-]{43}$ ]]
}

valid_short_id() {
    [[ $1 =~ ^[0-9a-fA-F]{2,16}$ ]] && ((${#1} % 2 == 0))
}

valid_wg_key() {
    [[ $1 =~ ^[A-Za-z0-9+/]{43}=$ ]]
}

valid_ipv4() {
    [[ $1 =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]
}

valid_ipv6() {
    [[ $1 =~ ^[0-9a-fA-F:]+$ ]] && [[ $1 == *:*:* ]]
}

valid_reserved() {
    local re='^([0-9]{1,3}),([0-9]{1,3}),([0-9]{1,3})$'
    [[ $1 =~ $re ]] && ((10#${BASH_REMATCH[1]} <= 255 && 10#${BASH_REMATCH[2]} <= 255 && 10#${BASH_REMATCH[3]} <= 255))
}

valid_endpoint() {
    [[ $1 =~ ^[A-Za-z0-9.-]+:[0-9]{1,5}$ ]]
}

credential_state() {
    if [ -z "$1" ]; then
        printf '空'
    elif "$2" "$1"; then
        printf '合法'
    else
        printf '格式错误'
    fi
}

json_string() {
    { grep -oE "$2" <<<"$1" || true; } | awk -F'"' 'NR == 1 {print $4}'
}

json_escape() {
    local value=${1//\\/\\\\}
    printf '%s' "${value//\"/\\\"}"
}

load_warp_list_snapshot() {
    if [ ! -f "$WARP_LIST_FILE" ]; then
        info "节点未启用 WARP 订阅列表或从未同步成功，面板模板只带内置分流域名"
        return
    fi
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        warp_custom_domains+="$line"$'\n'
        warp_custom_count=$((warp_custom_count + 1))
    done <"$WARP_LIST_FILE"
    info "WARP 订阅列表快照: ${warp_custom_count} 条自定义域名一并迁入面板，之后由面板管理 (快照来自上次成功同步)"
}

first_match() {
    { grep -oE "$1" <<<"$2" || true; } | head -n 1
}

json_number() {
    { grep -oE "\"$2\":[0-9]+" <<<"$1" || true; } | awk -F: 'NR == 1 {print $2}'
}

config_port() {
    { grep -oE '"port":[0-9]+' <<<"$1" || true; } | awk -F: 'NR == 1 {print $2}'
}

rand_hex() {
    od -An -N"$1" -tx1 /dev/urandom | tr -d ' \n'
}

key_from_output() {
    awk -v want="$1" -F': *' '
        { label = tolower($1) }
        want == "public" && (label ~ /^public ?key$/ || label ~ /^password/) { print $2; exit }
    ' <<<"$2"
}

derive_public_key() {
    local output
    output=$(docker run --rm "$NODE_IMAGE" xray x25519 -i "$private_key" 2>&1 || true)
    public_key=$(key_from_output public "$output")
    if ! valid_key "$public_key"; then
        fail "无法由节点私钥推导公钥 (xray x25519 -i 输出: ${output:0:160})，面板分享链接需要公钥，无法继续迁移"
    fi
    info "已由节点私钥推导公钥并写入面板入站，面板生成的分享链接将带 pbk 参数"
}

banner() {
    step "========================================"
    step "  3x-ui 面板一键安装 (接管 Reality 节点)"
    step "========================================"
    echo
}

require_root() {
    [ "$(id -u)" -eq 0 ] || fail "请使用 root 运行 (当前 uid: $(id -u))，可先执行 sudo -i"
}

require_curl() {
    command -v curl >/dev/null 2>&1 || fail "缺少 curl，请先安装 (apt-get install -y curl 或 yum install -y curl)"
}

check_existing_panel() {
    if ! docker container inspect "$XUI_CONTAINER" >/dev/null 2>&1; then
        return
    fi
    if [ -f "$XUI_INFO_FILE" ]; then
        step "面板容器 ${XUI_CONTAINER} 已存在，不重复安装、不重置账密，现有面板信息如下"
        echo
        cat "$XUI_INFO_FILE"
        exit 0
    fi
    fail "面板容器 ${XUI_CONTAINER} 已存在但缺少信息文件 ${XUI_INFO_FILE}，为避免覆盖已有面板数据本次不重装；可执行 docker exec ${XUI_CONTAINER} /app/x-ui setting -show 查看面板端口与路径"
}

ensure_node_installed() {
    if [ -f "$NODE_CONFIG_FILE" ]; then
        info "发现已安装的 Reality 节点配置 ${NODE_CONFIG_FILE}，将无损迁移进面板 (客户端无需重新导入)"
        return
    fi
    info "未发现 Reality 节点配置 ${NODE_CONFIG_FILE}，先调用 ${INSTALLER_NAME} 安装节点 (交互提问原样透传)"
    local installer script_dir
    script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    if [ -f "${script_dir}/${INSTALLER_NAME}" ]; then
        installer="${script_dir}/${INSTALLER_NAME}"
        info "使用同目录的安装脚本 ${installer}"
    else
        tmp_installer=$(mktemp)
        curl -fsSL "$INSTALLER_URL" -o "$tmp_installer" || fail "下载安装脚本失败 (${INSTALLER_URL})，可将 ${INSTALLER_NAME} 放到本脚本同目录后重试"
        installer=$tmp_installer
        info "同目录未找到 ${INSTALLER_NAME}，已从 ${INSTALLER_URL} 下载"
    fi
    bash "$installer" || fail "节点安装失败，面板未开始安装，可修复后重新执行本脚本"
    [ -f "$NODE_CONFIG_FILE" ] || fail "安装脚本执行完毕但 ${NODE_CONFIG_FILE} 仍不存在，无法迁移，面板未开始安装"
}

load_node_config() {
    local flat
    flat=$(tr -d ' \t\r\n' <"$NODE_CONFIG_FILE")
    port=$(config_port "$flat")
    sni=$(json_string "$flat" '"serverNames":\["[^"]*"')
    uuid=$(json_string "$flat" '"id":"[^"]*"')
    private_key=$(json_string "$flat" '"privateKey":"[^"]*"')
    short_id=$(json_string "$flat" '"shortIds":\["[^"]*"')
    if ! valid_port "$port"; then
        fail "已有配置中的端口不合法 (值: ${port:-空})，无法迁移，请先用 ${INSTALLER_NAME} 重装节点"
    fi
    port=$((10#$port))
    if ! valid_domain "$sni" || ! valid_uuid "$uuid" || ! valid_key "$private_key" || ! valid_short_id "$short_id"; then
        fail "已有配置的迁移凭据不完整 (SNI: $(credential_state "$sni" valid_domain), UUID: $(credential_state "$uuid" valid_uuid), 私钥: $(credential_state "$private_key" valid_key), ShortId: $(credential_state "$short_id" valid_short_id))，无法无损迁移，请先用 ${INSTALLER_NAME} 重装节点"
    fi
    info "迁移参数: 端口 ${port}, SNI ${sni}, UUID ${uuid}, ShortId ${short_id} (全部原样带入面板)"
    load_node_warp "$flat"
    load_node_fallback "$flat"
}

load_node_warp() {
    local flat=$1 addresses
    if [[ $flat != *'"protocol":"wireguard"'* ]]; then
        info "已有节点未开启 WARP，面板模板保持默认出站"
        return
    fi
    addresses=$(first_match '"address":\[[^]]*\]' "$flat")
    warp_secret=$(json_string "$flat" '"secretKey":"[^"]*"')
    warp_v4=$(first_match '[0-9.]+/32' "$addresses")
    warp_v4=${warp_v4%/32}
    warp_v6=$(first_match '[0-9a-fA-F:]+/128' "$addresses")
    warp_v6=${warp_v6%/128}
    warp_reserved=$(first_match '[0-9]+,[0-9]+,[0-9]+' "$(first_match '"reserved":\[[0-9]+,[0-9]+,[0-9]+\]' "$flat")")
    warp_peer=$(json_string "$flat" '"publicKey":"[^"]*"')
    warp_endpoint=$(json_string "$flat" '"endpoint":"[^"]*"')
    if ! valid_wg_key "$warp_secret" || ! valid_ipv4 "$warp_v4" || ! valid_ipv6 "$warp_v6" || ! valid_reserved "$warp_reserved" || ! valid_wg_key "$warp_peer" || ! valid_endpoint "$warp_endpoint"; then
        fail "已有节点开启了 WARP 但账号信息不完整 (私钥: $(credential_state "$warp_secret" valid_wg_key), IPv4: $(credential_state "$warp_v4" valid_ipv4), IPv6: $(credential_state "$warp_v6" valid_ipv6), reserved: $(credential_state "$warp_reserved" valid_reserved), 对端公钥: $(credential_state "$warp_peer" valid_wg_key), endpoint: $(credential_state "$warp_endpoint" valid_endpoint))，无法无损迁移；请先用 ${INSTALLER_NAME} 重装节点修复 WARP 配置"
    fi
    warp_enabled=true
    info "已有节点开启了 WARP (地址: ${warp_v4}, ${warp_v6})，账号原样迁入面板模板，出站 tag 为 warp，可在面板 WARP 页继续管理"
    load_warp_list_snapshot
}

load_node_fallback() {
    local flat=$1 up down
    up=$(first_match '"limitFallbackUpload":\{[^}]*\}' "$flat")
    down=$(first_match '"limitFallbackDownload":\{[^}]*\}' "$flat")
    fallback_up_after=$(json_number "$up" afterBytes)
    fallback_up_rate=$(json_number "$up" bytesPerSec)
    fallback_up_burst=$(json_number "$up" burstBytesPerSec)
    fallback_down_after=$(json_number "$down" afterBytes)
    fallback_down_rate=$(json_number "$down" bytesPerSec)
    fallback_down_burst=$(json_number "$down" burstBytesPerSec)
    if [ "${fallback_up_rate:-0}" -eq 0 ] && [ "${fallback_down_rate:-0}" -eq 0 ]; then
        info "已有节点未开启回落限速，迁移后同样不开启"
        return
    fi
    if [ -z "$fallback_up_after" ] || [ -z "$fallback_up_burst" ] || [ -z "$fallback_down_after" ] || [ -z "$fallback_down_burst" ] || [ "${fallback_up_rate:-0}" -le 0 ] || [ "${fallback_down_rate:-0}" -le 0 ]; then
        fail "已有节点的回落限速参数不完整 (上行: ${fallback_up_after:-空}/${fallback_up_rate:-空}/${fallback_up_burst:-空}, 下行: ${fallback_down_after:-空}/${fallback_down_rate:-空}/${fallback_down_burst:-空})，无法无损迁移；请先用 ${INSTALLER_NAME} 重装节点修复"
    fi
    fallback_enabled=true
    info "已有节点开启了回落限速 (上行 ${fallback_up_after}/${fallback_up_rate}/${fallback_up_burst}, 下行 ${fallback_down_after}/${fallback_down_rate}/${fallback_down_burst})，六个值原样迁入面板"
}

ensure_docker() {
    if command -v docker >/dev/null 2>&1; then
        info "Docker 已安装 ($(docker --version 2>/dev/null || echo 版本未知))，跳过安装"
    else
        install_docker
        if command -v systemctl >/dev/null 2>&1; then
            systemctl enable --now docker || fail "systemctl enable --now docker 失败"
        fi
    fi
    if ! docker info >/dev/null 2>&1; then
        info "Docker 守护进程未运行，尝试启动"
        if command -v systemctl >/dev/null 2>&1; then
            systemctl start docker || true
        else
            service docker start || true
        fi
        docker info >/dev/null 2>&1 || fail "Docker 守护进程无法启动，请检查: systemctl status docker"
        info "Docker 守护进程已启动"
    fi
}

install_docker() {
    local os_id package_manager tmp_get_docker
    step "未检测到 Docker，正在通过 get.docker.com 安装..."
    tmp_get_docker=$(mktemp)
    if ! curl -fsSL https://get.docker.com -o "$tmp_get_docker"; then
        rm -f "$tmp_get_docker"
        fail "下载 get.docker.com 安装脚本失败"
    fi
    if sh "$tmp_get_docker" </dev/null; then
        rm -f "$tmp_get_docker"
        return
    fi
    rm -f "$tmp_get_docker"
    os_id=$(awk -F= '$1 == "ID" {gsub(/"/, "", $2); print $2}' /etc/os-release 2>/dev/null || true)
    case $os_id in
        rocky | almalinux | ol | centos | rhel) ;;
        *) fail "Docker 安装失败 (系统 ID: ${os_id:-未知})，请查看上方 get.docker.com 的输出" ;;
    esac
    package_manager=dnf
    if ! command -v dnf >/dev/null 2>&1; then
        package_manager=yum
    fi
    info "get.docker.com 安装失败，系统 ${os_id} 属于 RHEL 系，改用 Docker 官方 centos 源通过 ${package_manager} 安装"
    curl -fsSL https://download.docker.com/linux/centos/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo || fail "下载 Docker 官方 centos 源失败"
    "$package_manager" install -y docker-ce docker-ce-cli containerd.io </dev/null || fail "通过 Docker 官方 centos 源安装失败 (${package_manager} install docker-ce docker-ce-cli containerd.io)"
    info "已通过 Docker 官方 centos 源安装 ($(docker --version 2>/dev/null || echo 版本未知))"
}

port_listening() {
    [ -n "$(ss -Htln "sport = :${1}" 2>/dev/null || true)" ]
}

pick_panel_port() {
    local candidate attempt
    if [ -n "${XUI_PORT:-}" ]; then
        valid_port "$XUI_PORT" || fail "环境变量 XUI_PORT=${XUI_PORT} 不合法，需为 1-65535 的整数"
        panel_port=$((10#$XUI_PORT))
        if command -v ss >/dev/null 2>&1 && port_listening "$panel_port"; then
            fail "指定的面板端口 ${panel_port} 已被占用 (XUI_PORT)，请换一个"
        fi
        info "面板端口: ${panel_port} (来自环境变量 XUI_PORT)"
        return
    fi
    if ! command -v ss >/dev/null 2>&1; then
        panel_port=$((PANEL_PORT_MIN + RANDOM % (PANEL_PORT_MAX - PANEL_PORT_MIN + 1)))
        info "未找到 ss 命令，跳过端口占用检查，面板端口随机取 ${panel_port}"
        return
    fi
    for ((attempt = 1; attempt <= PANEL_PORT_TRIES; attempt++)); do
        candidate=$((PANEL_PORT_MIN + RANDOM % (PANEL_PORT_MAX - PANEL_PORT_MIN + 1)))
        if [ "$candidate" -ne "$port" ] && ! port_listening "$candidate"; then
            panel_port=$candidate
            info "面板端口: ${panel_port} (在 ${PANEL_PORT_MIN}-${PANEL_PORT_MAX} 随机选取，第 ${attempt} 次命中空闲端口)"
            return
        fi
    done
    fail "随机尝试 ${PANEL_PORT_TRIES} 次仍未找到空闲面板端口 (${PANEL_PORT_MIN}-${PANEL_PORT_MAX})，可用 XUI_PORT 手动指定"
}

generate_panel_credentials() {
    panel_user="admin-$(rand_hex 3)"
    panel_pass=$(rand_hex 16)
    panel_path="/$(rand_hex 8)"
    info "面板账号已随机生成 (用户名 ${panel_user}, 密码与访问路径见安装完成后的输出)"
}

start_panel_container() {
    step "正在拉取面板镜像 ${XUI_IMAGE}..."
    docker pull "$XUI_IMAGE" || fail "拉取镜像 ${XUI_IMAGE} 失败"
    mkdir -p "$XUI_DB_DIR"
    docker run -d \
        --name "$XUI_CONTAINER" \
        --restart always \
        --net host \
        --log-driver json-file \
        --log-opt max-size="$LOG_MAX_SIZE" \
        --log-opt max-file="$LOG_MAX_FILE" \
        -v "${XUI_DB_DIR}:${XUI_DB_DIR}" \
        "$XUI_IMAGE" >/dev/null || fail "启动面板容器 ${XUI_CONTAINER} 失败"
    info "面板容器已启动，数据库持久化在 ${XUI_DB_DIR}，日志按 json-file 轮转 (单文件 ${LOG_MAX_SIZE}, 最多 ${LOG_MAX_FILE} 份)"
}

wait_panel_db() {
    local i
    for ((i = 1; i <= PANEL_WAIT_SECONDS; i++)); do
        if docker exec "$XUI_CONTAINER" /app/x-ui setting -show >/dev/null 2>&1; then
            info "面板数据库已就绪 (等待 ${i}s)"
            return
        fi
        sleep 1
    done
    docker logs --tail 20 "$XUI_CONTAINER" >&2 || true
    fail "等待 ${PANEL_WAIT_SECONDS}s 后面板数据库仍未就绪，上面是容器日志"
}

configure_panel() {
    local token_output
    docker exec "$XUI_CONTAINER" /app/x-ui setting \
        -port "$panel_port" -username "$panel_user" -password "$panel_pass" -webBasePath "$panel_path" \
        || fail "写入面板端口/账密/路径失败"
    token_output=$(docker exec "$XUI_CONTAINER" /app/x-ui setting -getApiToken 2>&1) || fail "生成面板 API Token 失败 (输出: ${token_output:0:160})"
    api_token=$(awk '$1 == "apiToken:" {print $2; exit}' <<<"$token_output")
    if [ -z "$api_token" ]; then
        fail "无法从 x-ui setting -getApiToken 输出解析 API Token (输出: ${token_output:0:160})"
    fi
    docker restart "$XUI_CONTAINER" >/dev/null || fail "重启面板容器使新端口/路径生效失败"
    info "面板端口/账密/随机路径已写入，API Token 已生成，容器已重启"
}

wait_panel_http() {
    local i code
    for ((i = 1; i <= PANEL_WAIT_SECONDS; i++)); do
        code=$(curl -s -o /dev/null -w '%{http_code}' --noproxy 127.0.0.1 --max-time 3 "http://127.0.0.1:${panel_port}${panel_path}/" 2>/dev/null || true)
        if [[ $code =~ ^(2|3)[0-9][0-9]$ ]]; then
            info "面板 HTTP 已就绪 (http://127.0.0.1:${panel_port}${panel_path}/ 返回 ${code}, 等待 ${i}s)"
            return
        fi
        sleep 1
    done
    docker logs --tail 20 "$XUI_CONTAINER" >&2 || true
    fail "等待 ${PANEL_WAIT_SECONDS}s 后面板 HTTP 仍未就绪 (最后状态码: ${code:-无响应})，上面是容器日志"
}

api_post_form() {
    local path=$1 response
    shift
    response=$(curl -sS --noproxy 127.0.0.1 --max-time 30 -H "Authorization: Bearer ${api_token}" "$@" "http://127.0.0.1:${panel_port}${panel_path}/panel/api${path}" 2>&1) || {
        printf '%s' "$response"
        return 1
    }
    printf '%s' "$response"
    [[ $(tr -d ' \t\r\n' <<<"$response") == *'"success":true'* ]]
}

render_inbound_settings() {
    cat <<EOF
{
  "clients": [
    {
      "id": "${uuid}",
      "flow": "${FLOW}",
      "email": "${CLIENT_EMAIL}"
    }
  ],
  "decryption": "none"
}
EOF
}

render_fallback_limits() {
    cat <<EOF
,
          "limitFallbackUpload": {
            "afterBytes": ${fallback_up_after},
            "bytesPerSec": ${fallback_up_rate},
            "burstBytesPerSec": ${fallback_up_burst}
          },
          "limitFallbackDownload": {
            "afterBytes": ${fallback_down_after},
            "bytesPerSec": ${fallback_down_rate},
            "burstBytesPerSec": ${fallback_down_burst}
          }
EOF
}

render_inbound_stream() {
    local fallback_limits=""
    if [ "$fallback_enabled" = true ]; then
        fallback_limits=$(render_fallback_limits)
    fi
    cat <<EOF
{
  "network": "tcp",
  "security": "reality",
  "realitySettings": {
    "show": false,
    "dest": "${sni}:443",
    "xver": 0,
    "serverNames": [
      "${sni}"
    ],
    "privateKey": "${private_key}",
    "shortIds": [
      "${short_id}"
    ],
    "settings": {
      "publicKey": "${public_key}",
      "fingerprint": "${FINGERPRINT}"
    }${fallback_limits}
  }
}
EOF
}

render_inbound_sniffing() {
    cat <<EOF
{
  "enabled": true,
  "destOverride": [
    "http",
    "tls",
    "quic"
  ]
}
EOF
}

add_panel_inbound() {
    local response flat
    response=$(api_post_form /inbounds/add \
        --data-urlencode "remark=Reality-${server_ip}" \
        --data-urlencode "tag=in-${port}-tcp" \
        --data-urlencode "protocol=vless" \
        --data-urlencode "port=${port}" \
        --data-urlencode "enable=false" \
        --data-urlencode "up=0" \
        --data-urlencode "down=0" \
        --data-urlencode "total=0" \
        --data-urlencode "expiryTime=0" \
        --data-urlencode "settings=$(render_inbound_settings)" \
        --data-urlencode "streamSettings=$(render_inbound_stream)" \
        --data-urlencode "sniffing=$(render_inbound_sniffing)") || fail "面板创建入站失败 (响应: ${response:0:300})，旧容器与配置保持原样"
    flat=$(tr -d ' \t\r\n' <<<"$response")
    inbound_id=$(json_number "$flat" id)
    if [ -z "$inbound_id" ]; then
        fail "面板入站已创建但无法解析入站 id (响应: ${response:0:300})，请在面板里手动检查后重试"
    fi
    info "面板入站已创建 (id ${inbound_id}, 备注 Reality-${server_ip}, 用户 ${CLIENT_EMAIL}, 先保持禁用等旧容器让出端口)"
}

render_warp_outbound() {
    local endpoint_strategy=ForceIPv4
    if [[ $server_ip == *:* ]]; then
        endpoint_strategy=ForceIPv6
    fi
    cat <<EOF
    {
      "tag": "warp",
      "protocol": "wireguard",
      "targetStrategy": "${WARP_TARGET_STRATEGY}",
      "streamSettings": {
        "sockopt": {
          "domainStrategy": "${endpoint_strategy}"
        }
      },
      "settings": {
        "secretKey": "${warp_secret}",
        "address": [
          "${warp_v4}/32",
          "${warp_v6}/128"
        ],
        "peers": [
          {
            "publicKey": "${warp_peer}",
            "allowedIPs": [
              "0.0.0.0/0",
              "::/0"
            ],
            "endpoint": "${warp_endpoint}"
          }
        ],
        "reserved": [${warp_reserved//,/, }],
        "mtu": ${WARP_MTU},
        "noKernelTun": true
      }
    }
EOF
}

render_warp_domains() {
    printf '          "%s"' "${WARP_DOMAINS[0]}"
    local domain
    for domain in "${WARP_DOMAINS[@]:1}"; do
        printf ',\n          "%s"' "$domain"
    done
    [ -n "$warp_custom_domains" ] || return 0
    while IFS= read -r domain; do
        [ -n "$domain" ] || continue
        printf ',\n          "%s"' "$(json_escape "$domain")"
    done <<<"$warp_custom_domains"
}

render_panel_template() {
    cat <<EOF
{
  "api": {
    "services": [
      "HandlerService",
      "LoggerService",
      "StatsService",
      "RoutingService"
    ],
    "tag": "api"
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 62789,
      "protocol": "tunnel",
      "settings": {
        "rewriteAddress": "127.0.0.1"
      },
      "tag": "api"
    }
  ],
  "log": {
    "access": "none",
    "dnsLog": false,
    "error": "",
    "loglevel": "warning",
    "maskAddress": ""
  },
  "metrics": {
    "listen": "127.0.0.1:11111",
    "tag": "metrics_out"
  },
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {
        "finalRules": [
          { "action": "block", "ip": ["geoip:private"] },
          { "action": "allow" }
        ]
      },
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    },
$(render_warp_outbound)
  ],
  "policy": {
    "levels": {
      "0": {
        "statsUserDownlink": true,
        "statsUserUplink": true
      }
    },
    "system": {
      "statsInboundDownlink": true,
      "statsInboundUplink": true,
      "statsOutboundDownlink": false,
      "statsOutboundUplink": false
    }
  },
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "inboundTag": [
          "api"
        ],
        "outboundTag": "api",
        "type": "field"
      },
      {
        "type": "field",
        "domain": [
$(render_warp_domains)
        ],
        "outboundTag": "warp"
      },
      {
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked",
        "type": "field"
      },
      {
        "outboundTag": "blocked",
        "protocol": [
          "bittorrent"
        ],
        "type": "field"
      }
    ]
  },
  "stats": {}
}
EOF
}

migrate_panel_template() {
    local response
    if [ "$warp_enabled" != true ]; then
        info "节点未开启 WARP，面板 Xray 模板保持默认，仅靠内置模板即可正常统计流量"
        return
    fi
    response=$(api_post_form /xray/update \
        --data-urlencode "xraySetting=$(render_panel_template)") || fail "写入面板 Xray 模板失败 (响应: ${response:0:300})，旧容器与配置保持原样"
    if [ "$warp_custom_count" -gt 0 ]; then
        info "WARP 出站与分流规则已迁入面板 Xray 模板并通过面板校验 (内置 AI / Netflix / Disney+ 加订阅快照 ${warp_custom_count} 条走 warp 出站)"
    else
        info "WARP 出站与分流规则已迁入面板 Xray 模板并通过面板校验 (AI / Netflix / Disney+ 走 warp 出站)"
    fi
}

remove_warp_sync() {
    if [ ! -f "$WARP_SYNC_FILE" ] && [ ! -f "$WARP_SYNC_STATE_FILE" ]; then
        return
    fi
    if command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now "${WARP_SYNC_UNIT}.timer" >/dev/null 2>&1 || true
        rm -f "/etc/systemd/system/${WARP_SYNC_UNIT}.timer" "/etc/systemd/system/${WARP_SYNC_UNIT}.service"
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    if command -v crontab >/dev/null 2>&1 && crontab -l >/dev/null 2>&1; then
        local current
        current=$(crontab -l 2>/dev/null || true)
        if [[ $current == *"$WARP_SYNC_CRON_MARK"* ]]; then
            { grep -vF "$WARP_SYNC_CRON_MARK" <<<"$current" || true; } | crontab - 2>/dev/null || true
        fi
    fi
    rm -f "$WARP_SYNC_FILE" "$WARP_SYNC_STATE_FILE"
    rm -rf "${NODE_CONFIG_DIR}/warp-sync.lock"
    info "WARP 订阅定时同步器已移除，订阅域名已快照进面板，之后改分流规则请在面板的 Xray 模板里操作 (${WARP_LIST_FILE} 保留作快照记录)"
}

remove_node_container() {
    if docker container inspect "$NODE_CONTAINER" >/dev/null 2>&1; then
        docker rm -f -v "$NODE_CONTAINER" >/dev/null || fail "移除旧容器 ${NODE_CONTAINER} 失败，面板入站保持禁用，节点仍由旧容器服务"
        node_removed=true
        info "旧容器 ${NODE_CONTAINER} 已移除，端口 ${port} 让给面板；${NODE_CONFIG_DIR} 下的配置与信息文件保留用于回滚"
    else
        info "旧容器 ${NODE_CONTAINER} 不在运行，无需移除，直接由面板接管端口 ${port}"
    fi
}

rollback_to_node_container() {
    info "迁移未成功，正在回滚: 禁用面板入站并恢复旧容器 ${NODE_CONTAINER}"
    api_post_form "/inbounds/setEnable/${inbound_id}" --data-urlencode "enable=false" >/dev/null 2>&1 || true
    api_post_form /server/restartXrayService >/dev/null 2>&1 || true
    if [ "$node_removed" = true ]; then
        if docker run -d \
            --name "$NODE_CONTAINER" \
            --restart always \
            --net host \
            --log-driver json-file \
            --log-opt max-size="$LOG_MAX_SIZE" \
            --log-opt max-file="$LOG_MAX_FILE" \
            -v "${NODE_CONFIG_DIR}:${NODE_CONFIG_DIR}" \
            "$NODE_IMAGE" >/dev/null 2>&1; then
            info "旧容器 ${NODE_CONTAINER} 已按原配置恢复运行，客户端不受影响；面板容器保留但入站已禁用"
        else
            info "注意: 旧容器恢复失败，请手动执行: docker run -d --name ${NODE_CONTAINER} --restart always --net host -v ${NODE_CONFIG_DIR}:${NODE_CONFIG_DIR} ${NODE_IMAGE}"
        fi
    fi
}

handover_to_panel() {
    local response
    response=$(api_post_form "/inbounds/setEnable/${inbound_id}" --data-urlencode "enable=true") || {
        rollback_to_node_container
        fail "启用面板入站失败 (响应: ${response:0:300})，已回滚"
    }
    remove_node_container
    if response=$(api_post_form /server/restartXrayService); then
        info "面板入站已启用，面板 Xray 已重启，开始接管端口 ${port}"
    else
        info "注意: 重启面板 Xray 接口未返回成功 (响应: ${response:0:200})，面板可能已通过热更新应用配置，以端口监听校验为准"
    fi
}

wait_node_listening() {
    local i
    for ((i = 1; i <= NODE_WAIT_SECONDS; i++)); do
        sleep 1
        if ! command -v ss >/dev/null 2>&1; then
            if [ "$i" -ge 5 ]; then
                info "无 ss 命令，未校验端口监听，面板 Xray 已重启 ${i}s"
                return
            fi
            continue
        fi
        if port_listening "$port"; then
            info "面板 Xray 已监听 TCP ${port} (等待 ${i}s)，节点接管完成"
            return
        fi
    done
    docker logs --tail 20 "$XUI_CONTAINER" >&2 || true
    rollback_to_node_container
    fail "等待 ${NODE_WAIT_SECONDS}s 后面板 Xray 仍未监听端口 ${port}，已回滚到旧容器，上面是面板容器日志"
}

detect_server_ip() {
    local svc ip
    local ipv4_re='^[0-9]{1,3}(\.[0-9]{1,3}){3}$'
    local ipv6_re='^[0-9a-fA-F:]*:[0-9a-fA-F:]*$'
    for svc in ifconfig.me ip.sb ipinfo.io/ip; do
        ip=$(curl -4 -fsS --max-time 6 "$svc" 2>/dev/null | tr -d '[:space:]' || true)
        if [[ $ip =~ $ipv4_re ]]; then
            server_ip=$ip
            info "服务器 IP: ${server_ip} (来自 ${svc})"
            return
        fi
        info "从 ${svc} 获取 IPv4 失败 (返回: ${ip:0:40})，尝试下一个"
    done
    for svc in ifconfig.me ip.sb; do
        ip=$(curl -6 -fsS --max-time 6 "$svc" 2>/dev/null | tr -d '[:space:]' || true)
        if [[ $ip =~ $ipv6_re ]]; then
            server_ip=$ip
            info "服务器 IP: ${server_ip} (IPv6，来自 ${svc})"
            return
        fi
        info "从 ${svc} 获取 IPv6 失败 (返回: ${ip:0:40})，尝试下一个"
    done
    ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") {print $(i + 1); exit}}' || true)
    [ -n "$ip" ] || fail "无法获取服务器 IP: ifconfig.me / ip.sb / ipinfo.io 均查询失败，且本机没有默认路由"
    server_ip=$ip
    info "注意: 公网 IP 查询全部失败，改用本机出口网卡地址 ${server_ip}；若这是内网地址，请在浏览器里手动换成服务器公网 IP"
}

open_panel_firewall() {
    local status
    if command -v ufw >/dev/null 2>&1; then
        status=$(LC_ALL=C ufw status 2>/dev/null || true)
        if [[ $status == *"Status: active"* ]]; then
            if ufw allow "${panel_port}/tcp" >/dev/null; then
                info "ufw 已启用，已放行面板 TCP ${panel_port}"
            else
                info "注意: ufw 放行面板 TCP ${panel_port} 失败，请手动执行 ufw allow ${panel_port}/tcp"
            fi
            return
        fi
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        if firewall-cmd --permanent --add-port="${panel_port}/tcp" >/dev/null && firewall-cmd --reload >/dev/null; then
            info "firewalld 已启用，已放行面板 TCP ${panel_port}"
        else
            info "注意: firewalld 放行面板 TCP ${panel_port} 失败，请手动执行 firewall-cmd --permanent --add-port=${panel_port}/tcp && firewall-cmd --reload"
        fi
        return
    fi
    info "未检测到启用中的 ufw / firewalld，跳过系统防火墙放行；如云厂商有安全组，请自行放行面板 TCP ${panel_port}"
}

panel_host() {
    if [[ $server_ip == *:* ]]; then
        printf '[%s]' "$server_ip"
    else
        printf '%s' "$server_ip"
    fi
}

render_panel_info() {
    local hl=$1 off=$2
    cat <<EOF
============ 3x-ui 面板信息 ============
面板地址:    ${hl}http://$(panel_host):${panel_port}${panel_path}/${off}
用户名:      ${hl}${panel_user}${off}
密码:        ${hl}${panel_pass}${off}
========================================
接管节点:    ${hl}Reality-${server_ip}${off} (端口 ${port}, SNI ${sni})
迁移用户:    ${hl}${CLIENT_EMAIL}${off} (原 UUID，旧客户端无需重新导入)
WARP 分流:   ${hl}$([ "$warp_enabled" = true ] && printf '已迁入面板模板 (warp 出站)' || printf '未开启')${off}
WARP 订阅:   ${hl}$([ "$warp_custom_count" -gt 0 ] && printf '快照 %s 条已迁入面板, 定时同步器已移除' "$warp_custom_count" || printf '无订阅快照')${off}
回落限速:    ${hl}$([ "$fallback_enabled" = true ] && printf '已原样迁入' || printf '未开启')${off}
========================================
数据库:      ${XUI_DB_DIR} (容器重建不丢数据)
回滚备份:    ${NODE_CONFIG_DIR} (旧配置与客户端信息保留)
多用户管理:  登录面板 -> 入站列表 -> Reality-${server_ip} -> 添加客户端
========================================
EOF
}

show_panel_result() {
    (umask 077 && render_panel_info "" "" >"$XUI_INFO_FILE")
    echo
    step "========================================"
    step "  面板安装完成，节点已由面板接管！"
    step "========================================"
    echo
    render_panel_info "$YELLOW" "$NC"
    echo
    step "面板信息已保存到 ${XUI_INFO_FILE} (仅 root 可读)，随时可执行 cat ${XUI_INFO_FILE} 查看"
    step "旧客户端连接参数完全不变；之后加人/删人/看流量/设到期都在面板里操作"
    step "面板为 HTTP 明文，靠随机端口 + 随机路径 + 随机账密保护，请勿外传面板地址"
}

install_panel() {
    banner
    require_root
    require_curl
    ensure_docker
    check_existing_panel
    ensure_node_installed
    load_node_config
    derive_public_key
    detect_server_ip
    pick_panel_port
    generate_panel_credentials
    start_panel_container
    wait_panel_db
    configure_panel
    wait_panel_http
    add_panel_inbound
    migrate_panel_template
    handover_to_panel
    wait_node_listening
    remove_warp_sync
    open_panel_firewall
    show_panel_result
}

main() {
    case "${1:-}" in
        "") install_panel ;;
        *) fail "未知参数: $1，用法: bash onekey_3xui.sh (安装 3x-ui 面板并接管 Reality 节点)" ;;
    esac
}

main "$@"