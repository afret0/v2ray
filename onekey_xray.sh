#!/usr/bin/env bash
set -Eeuo pipefail

readonly XRAY_IMAGE="teddysun/xray"
readonly CONTAINER_NAME="xray-reality"
readonly CONFIG_DIR="/etc/xray"
readonly CONFIG_FILE="${CONFIG_DIR}/config.json"
readonly INFO_FILE="${CONFIG_DIR}/client-info.txt"
readonly DEFAULT_SNI="www.microsoft.com"
readonly DEFAULT_PORT="443"
readonly FLOW="xtls-rprx-vision"
readonly FINGERPRINT="chrome"
readonly HEALTH_WAIT_SECONDS=10

readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[1;33m'
readonly RED=$'\033[0;31m'
readonly NC=$'\033[0m'

sni=""
port=""
default_sni=$DEFAULT_SNI
default_port=$DEFAULT_PORT
reuse_credentials=false
old_uuid=""
old_private_key=""
old_short_id=""
uuid=""
private_key=""
public_key=""
short_id=""
server_ip=""
vless_link=""
tmp_config=""
tmp_get_docker=""

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
    if [ -n "$tmp_config" ]; then rm -f "$tmp_config"; fi
    if [ -n "$tmp_get_docker" ]; then rm -f "$tmp_get_docker"; fi
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

credential_state() {
    if [ -z "$1" ]; then
        printf '空'
    elif "$2" "$1"; then
        printf '合法'
    else
        printf '格式错误'
    fi
}

has_tty() {
    (exec </dev/tty) 2>/dev/null
}

json_string() {
    { grep -oE "$2" <<<"$1" || true; } | awk -F'"' 'NR == 1 {print $4}'
}

key_from_output() {
    awk -v want="$1" -F': *' '
        { label = tolower($1) }
        want == "private" && label ~ /^private ?key$/ { print $2; exit }
        want == "public" && (label ~ /^public ?key$/ || label ~ /^password/) { print $2; exit }
    ' <<<"$2"
}

output_labels() {
    awk -F':' 'NF > 1 {printf "%s%s", sep, $1; sep = ", "}' <<<"$1"
}

banner() {
    step "========================================"
    step "  VLESS + Reality 一键安装脚本"
    step "========================================"
    echo
}

require_root() {
    [ "$(id -u)" -eq 0 ] || fail "请使用 root 运行 (当前 uid: $(id -u))，可先执行 sudo -i"
}

require_curl() {
    command -v curl >/dev/null 2>&1 || fail "缺少 curl，请先安装 (apt-get install -y curl 或 yum install -y curl)"
}

load_existing_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        info "未发现已有配置 ${CONFIG_FILE}，按全新安装处理"
        return
    fi
    local flat old_sni old_port
    flat=$(tr -d ' \t\r\n' <"$CONFIG_FILE")
    old_sni=$(json_string "$flat" '"serverNames":\["[^"]*"')
    old_port=$({ grep -oE '"port":[0-9]+' <<<"$flat" || true; } | awk -F: 'NR == 1 {print $2}')
    old_uuid=$(json_string "$flat" '"id":"[^"]*"')
    old_private_key=$(json_string "$flat" '"privateKey":"[^"]*"')
    old_short_id=$(json_string "$flat" '"shortIds":\["[^"]*"')
    info "发现已有配置 ${CONFIG_FILE}，按重装处理"

    if valid_domain "$old_sni"; then
        default_sni=$old_sni
        info "沿用已安装的 SNI 作为默认值: ${default_sni}"
    else
        info "已有配置中的 SNI 不合法 (值: ${old_sni:-空})，默认值仍为 ${DEFAULT_SNI}"
    fi

    if valid_port "$old_port"; then
        default_port=$((10#$old_port))
        info "沿用已安装的端口作为默认值: ${default_port}"
    else
        info "已有配置中的端口不合法 (值: ${old_port:-空})，默认值仍为 ${DEFAULT_PORT}"
    fi

    if valid_uuid "$old_uuid" && valid_key "$old_private_key" && valid_short_id "$old_short_id"; then
        reuse_credentials=true
        info "已有配置中的 UUID / 私钥 / ShortId 完整，本次复用，旧客户端无需更换密钥"
        return
    fi
    info "注意: 已有配置中的 UUID / 私钥 / ShortId 不完整 (UUID: $(credential_state "$old_uuid" valid_uuid), 私钥: $(credential_state "$old_private_key" valid_key), ShortId: $(credential_state "$old_short_id" valid_short_id))，将重新生成，旧客户端需重新导入"
}

choose_sni() {
    if [ -n "${XRAY_SNI:-}" ]; then
        valid_domain "$XRAY_SNI" || fail "环境变量 XRAY_SNI=${XRAY_SNI} 不是合法域名 (示例: www.microsoft.com)"
        sni=$XRAY_SNI
        info "伪装目标 (dest/SNI): ${sni} (来自环境变量 XRAY_SNI)"
        return
    fi
    if ! has_tty; then
        sni=$default_sni
        info "伪装目标 (dest/SNI): ${sni} (无交互终端且未设置 XRAY_SNI，取默认值)"
        return
    fi
    while true; do
        read -r -p "伪装目标域名 (SNI, 默认 ${default_sni}): " sni </dev/tty || sni=""
        sni=${sni:-$default_sni}
        valid_domain "$sni" && break
        info "${sni} 不是合法域名 (示例: www.microsoft.com)，请重新输入"
    done
    info "伪装目标 (dest/SNI): ${sni}"
}

choose_port() {
    if [ -n "${XRAY_PORT:-}" ]; then
        valid_port "$XRAY_PORT" || fail "环境变量 XRAY_PORT=${XRAY_PORT} 不合法，需为 1-65535 的整数"
        port=$((10#$XRAY_PORT))
        info "监听端口: ${port} (来自环境变量 XRAY_PORT)"
        return
    fi
    if ! has_tty; then
        port=$default_port
        info "监听端口: ${port} (无交互终端且未设置 XRAY_PORT，取默认值)"
        return
    fi
    while true; do
        read -r -p "监听端口 (默认 ${default_port}): " port </dev/tty || port=""
        port=${port:-$default_port}
        valid_port "$port" && break
        info "${port} 不合法，需为 1-65535 的整数，请重新输入"
    done
    port=$((10#$port))
    info "监听端口: ${port}"
}

check_sni_tls13() {
    local code=0 reason
    curl -s -o /dev/null --max-time 10 --tlsv1.3 "https://${sni}" || code=$?
    if [ "$code" -eq 0 ]; then
        info "伪装站 ${sni} 支持 TLS 1.3，检测通过"
        return
    fi
    case $code in
        6) reason="域名解析失败" ;;
        7) reason="无法连接 ${sni}:443" ;;
        28) reason="连接超时" ;;
        35) reason="TLS 握手失败，多半不支持 TLS 1.3" ;;
        *) reason="curl 退出码 ${code}" ;;
    esac
    info "注意: 伪装站 ${sni} 的 TLS 1.3 检测未通过 (${reason})；Reality 要求伪装站能从本机访问且支持 TLS 1.3，建议更换，本次继续安装"
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
    info "注意: 公网 IP 查询全部失败，改用本机出口网卡地址 ${server_ip}；若这是内网地址，请在客户端里手动换成服务器公网 IP"
}

ensure_docker() {
    if command -v docker >/dev/null 2>&1; then
        info "Docker 已安装 ($(docker --version 2>/dev/null || echo 版本未知))，跳过安装"
    else
        step "未检测到 Docker，正在通过 get.docker.com 安装..."
        tmp_get_docker=$(mktemp)
        curl -fsSL https://get.docker.com -o "$tmp_get_docker" || fail "下载 get.docker.com 安装脚本失败"
        sh "$tmp_get_docker" </dev/null || fail "Docker 安装失败，请查看上方 get.docker.com 的输出"
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
    if command -v systemctl >/dev/null 2>&1 && [ "$(systemctl is-enabled docker 2>/dev/null || true)" = disabled ]; then
        info "注意: Docker 未设置开机自启，服务器重启后 Xray 不会自动恢复，可执行 systemctl enable docker"
    fi
}

ensure_image() {
    if docker image inspect "$XRAY_IMAGE" >/dev/null 2>&1; then
        info "镜像 ${XRAY_IMAGE} 已存在，跳过拉取"
    else
        step "正在拉取镜像 ${XRAY_IMAGE}..."
        docker pull "$XRAY_IMAGE" || fail "拉取镜像 ${XRAY_IMAGE} 失败"
    fi
    info "Xray 版本: $(docker run --rm "$XRAY_IMAGE" xray version 2>/dev/null | awk 'NR == 1 {print $2}' || true)"
}

prepare_credentials() {
    local output
    if [ "$reuse_credentials" = true ]; then
        output=$(docker run --rm "$XRAY_IMAGE" xray x25519 -i "$old_private_key" 2>&1 || true)
        public_key=$(key_from_output public "$output")
        if valid_key "$public_key"; then
            uuid=$old_uuid
            private_key=$old_private_key
            short_id=$old_short_id
            info "复用已有 UUID: ${uuid}"
            info "复用已有私钥，推导出的 Public Key: ${public_key}"
            info "复用已有 Short ID: ${short_id}"
            return
        fi
        info "注意: 无法由已有私钥推导公钥 (xray x25519 -i 输出字段: $(output_labels "$output"))，改为重新生成，旧客户端需重新导入"
    fi
    step "正在生成 Reality 密钥对..."
    output=$(docker run --rm "$XRAY_IMAGE" xray x25519) || fail "执行 xray x25519 失败"
    private_key=$(key_from_output private "$output")
    public_key=$(key_from_output public "$output")
    if ! valid_key "$private_key" || ! valid_key "$public_key"; then
        fail "无法解析 xray x25519 的输出 (输出字段: $(output_labels "$output"))，Xray 输出格式可能又变了"
    fi
    uuid=$(cat /proc/sys/kernel/random/uuid)
    short_id=$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')
    info "Public Key: ${public_key}"
    info "UUID: ${uuid}"
    info "Short ID: ${short_id}"
}

check_port_free() {
    if ! command -v ss >/dev/null 2>&1; then
        info "未找到 ss 命令，跳过端口 ${port} 占用检查"
        return
    fi
    local listeners owners own_pid
    listeners=$(ss -Htlnp "sport = :${port}" 2>/dev/null || true)
    if [ -z "$listeners" ]; then
        info "端口 ${port} 空闲"
        return
    fi
    owners=$(sed -nE 's/.*users:\(\("([^"]+)",pid=([0-9]+).*/\2 \1/p' <<<"$listeners" | sort -u)
    own_pid=$(docker inspect -f '{{.State.Pid}}' "$CONTAINER_NAME" 2>/dev/null || echo 0)
    if [ -n "$owners" ] && [ "$own_pid" != 0 ] && ! grep -qv "^${own_pid} " <<<"$owners"; then
        info "端口 ${port} 由本脚本的 ${CONTAINER_NAME} 容器占用 (pid ${own_pid})，重装时会先移除它"
        return
    fi
    fail "端口 ${port} 已被占用 (pid/进程: $(tr '\n' ';' <<<"${owners:-$listeners}"))，需空闲或仅被 ${CONTAINER_NAME} 占用；请换端口 (XRAY_PORT) 或先停掉占用进程"
}

render_config() {
    cat <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${port},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "flow": "${FLOW}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
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
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF
}

write_and_test_config() {
    local output
    mkdir -p "$CONFIG_DIR"
    tmp_config="${CONFIG_DIR}/config.tmp.json"
    (umask 077 && render_config >"$tmp_config")
    if ! output=$(docker run --rm -v "${CONFIG_DIR}:${CONFIG_DIR}" "$XRAY_IMAGE" xray run -test -c "$tmp_config" 2>&1); then
        printf '%s\n' "$output" | tail -n 5 >&2
        fail "新配置未通过 xray run -test 校验，原配置 ${CONFIG_FILE} 保持不变"
    fi
    info "新配置已通过 xray run -test 校验"
}

start_container() {
    if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
        docker rm -f "$CONTAINER_NAME" >/dev/null
        info "已移除旧容器 ${CONTAINER_NAME}"
    fi
    mv -f "$tmp_config" "$CONFIG_FILE"
    tmp_config=""
    step "正在启动 Xray Reality..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart always \
        --net host \
        -v "${CONFIG_DIR}:${CONFIG_DIR}" \
        "$XRAY_IMAGE" >/dev/null || fail "启动容器 ${CONTAINER_NAME} 失败"
}

wait_for_xray() {
    local i status restarts
    for ((i = 1; i <= HEALTH_WAIT_SECONDS; i++)); do
        sleep 1
        status=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo missing)
        restarts=$(docker inspect -f '{{.RestartCount}}' "$CONTAINER_NAME" 2>/dev/null || echo 0)
        if [ "$status" != running ] || [ "$restarts" != 0 ]; then
            docker logs --tail 20 "$CONTAINER_NAME" >&2 || true
            fail "Xray 容器未能稳定运行 (状态: ${status}, 重启次数: ${restarts})，上面是容器日志"
        fi
        if ! command -v ss >/dev/null 2>&1; then
            if [ "$i" -ge 3 ]; then
                info "Xray 容器已稳定运行 ${i}s (无 ss 命令，未校验端口监听)"
                return
            fi
            continue
        fi
        if [ -n "$(ss -Htln "sport = :${port}" 2>/dev/null || true)" ]; then
            info "Xray 已启动并监听 TCP ${port} (容器状态: ${status}, 等待 ${i}s)"
            return
        fi
    done
    docker logs --tail 20 "$CONTAINER_NAME" >&2 || true
    fail "等待 ${HEALTH_WAIT_SECONDS}s 后端口 ${port} 仍未监听，上面是容器日志"
}

open_firewall() {
    local status
    if command -v ufw >/dev/null 2>&1; then
        status=$(LC_ALL=C ufw status 2>/dev/null || true)
        if [[ $status == *"Status: active"* ]]; then
            if ufw allow "${port}/tcp" >/dev/null; then
                info "ufw 已启用，已放行 TCP ${port}"
            else
                info "注意: ufw 放行 TCP ${port} 失败，请手动执行 ufw allow ${port}/tcp"
            fi
            return
        fi
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        if firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null && firewall-cmd --reload >/dev/null; then
            info "firewalld 已启用，已放行 TCP ${port}"
        else
            info "注意: firewalld 放行 TCP ${port} 失败，请手动执行 firewall-cmd --permanent --add-port=${port}/tcp && firewall-cmd --reload"
        fi
        return
    fi
    info "未检测到启用中的 ufw / firewalld，跳过系统防火墙放行；如云厂商有安全组，请自行放行 TCP ${port}"
}

render_client_info() {
    local hl=$1 off=$2
    cat <<EOF
============ 客户端配置信息 ============
协议:        ${hl}VLESS${off}
地址:        ${hl}${server_ip}${off}
端口:        ${hl}${port}${off}
UUID:        ${hl}${uuid}${off}
流控:        ${hl}${FLOW}${off}
传输协议:    ${hl}tcp${off}
传输层安全:  ${hl}reality${off}
SNI:         ${hl}${sni}${off}
Fingerprint: ${hl}${FINGERPRINT}${off}
PublicKey:   ${hl}${public_key}${off}
ShortId:     ${hl}${short_id}${off}
========================================

分享链接:
${hl}${vless_link}${off}
EOF
}

show_result() {
    local host=$server_ip
    if [[ $host == *:* ]]; then
        host="[${host}]"
    fi
    vless_link="vless://${uuid}@${host}:${port}?encryption=none&flow=${FLOW}&security=reality&sni=${sni}&fp=${FINGERPRINT}&pbk=${public_key}&sid=${short_id}&type=tcp#Reality-${server_ip}"
    (umask 077 && render_client_info "" "" >"$INFO_FILE")
    echo
    step "========================================"
    step "  安装完成！"
    step "========================================"
    echo
    render_client_info "$YELLOW" "$NC"
    echo
    step "以上信息已保存到 ${INFO_FILE}，随时可执行 cat ${INFO_FILE} 查看"
    step "请妥善保存以上信息！"
}

main() {
    banner
    require_root
    require_curl
    load_existing_config
    choose_sni
    choose_port
    check_sni_tls13
    detect_server_ip
    ensure_docker
    ensure_image
    prepare_credentials
    check_port_free
    write_and_test_config
    start_container
    wait_for_xray
    open_firewall
    show_result
}

main "$@"
