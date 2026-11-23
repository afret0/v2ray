#!/usr/bin/env bash
set -Eeuo pipefail

readonly XRAY_IMAGE="teddysun/xray"
readonly CONTAINER_NAME="xray-reality"
readonly CONFIG_DIR="/etc/xray"
readonly CONFIG_FILE="${CONFIG_DIR}/config.json"
readonly INFO_FILE="${CONFIG_DIR}/client-info.txt"
readonly CLASH_FILE="${CONFIG_DIR}/clash.yaml"
readonly -a SNI_POOL=('www.samsung.com' 'www.amd.com' 'www.tesla.com' 'www.cisco.com' 'www.autodesk.com')
readonly DEFAULT_PORT="443"
readonly FLOW="xtls-rprx-vision"
readonly FINGERPRINT="chrome"
readonly FALLBACK_AFTER_BYTES_CENTER=10485760
readonly FALLBACK_BYTES_PER_SEC_CENTER=1048576
readonly FALLBACK_BURST_BYTES_PER_SEC_CENTER=5242880
readonly FALLBACK_JITTER_PERCENT=30
readonly SNI_PROBE_TIMEOUT=10
readonly HEALTH_WAIT_SECONDS=10
readonly BBR_SYSCTL_FILE="/etc/sysctl.d/99-xray-bbr.conf"
readonly LOG_MAX_SIZE="10m"
readonly LOG_MAX_FILE="3"
readonly WARP_API="https://api.cloudflareclient.com/v0a5641/reg"
readonly WARP_USER_AGENT="1.1.1.1/6.38.9-5641 (Android 16.0.0)"
readonly WARP_CLIENT_VERSION="a-6.38.9-5641"
readonly WARP_MTU=1280
readonly WARP_TARGET_STRATEGY="ForceIPv4v6"
readonly WARP_CHECK_CONTAINER="xray-warp-check"
readonly WARP_CHECK_URL="https://www.cloudflare.com/cdn-cgi/trace"
readonly -a WARP_DOMAINS=('geosite:category-ai-!cn' 'geosite:netflix' 'geosite:disney')
readonly WARP_SYNC_FILE="${CONFIG_DIR}/warp-sync.sh"
readonly WARP_LIST_FILE="${CONFIG_DIR}/warp-domains.txt"
readonly WARP_SYNC_STATE_FILE="${CONFIG_DIR}/warp-sync-state"
readonly WARP_SYNC_UNIT="xray-warp-sync"
readonly WARP_SYNC_INTERVAL="daily"
readonly WARP_SYNC_JITTER_SECONDS=1800
readonly WARP_SYNC_CRON_MARK="# xray warp sync"
readonly WARP_SYNC_MAX_LINES=1000
readonly WARP_SYNC_FETCH_TIMEOUT=20
readonly WARP_LIST_URL="https://raw.githubusercontent.com/afret0/v2ray/master/warp-domains.txt"

readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[1;33m'
readonly RED=$'\033[0;31m'
readonly NC=$'\033[0m'

sni=""
port=""
default_sni=""
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
tmp_warp_sync_script=""
installed_port=""
bbr_choice=""
bbr_status=""
warp_choice=""
default_warp="n"
reuse_warp=false
warp_enabled=false
warp_status=""
warp_failure=""
warp_secret=""
warp_v4=""
warp_v6=""
warp_reserved=""
warp_peer=""
warp_endpoint=""
warp_check_dir=""
warp_check_started=false
warp_list_url=""
default_warp_list_url=$WARP_LIST_URL
warp_list_reuse=false
warp_custom_domains=""
warp_custom_count=0
warp_list_status=""
warp_list_skipped=""
warp_list_skipped_count=0
warp_list_truncated=false
warp_sync_status=""
fallback_choice=""
default_fallback="n"
reuse_fallback=false
fallback_enabled=false
fallback_status=""
fallback_up_after=""
fallback_up_rate=""
fallback_up_burst=""
fallback_down_after=""
fallback_down_rate=""
fallback_down_burst=""

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
    if [ -n "$tmp_warp_sync_script" ]; then rm -f "$tmp_warp_sync_script"; fi
    if [ "$warp_check_started" = true ]; then docker rm -f -v "$WARP_CHECK_CONTAINER" >/dev/null 2>&1 || true; fi
    if [ -n "$warp_check_dir" ]; then rm -rf "$warp_check_dir"; fi
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

valid_url() {
    local re='^https://[A-Za-z0-9.-]+(/.*)?$'
    [[ $1 =~ $re ]] && [[ $1 != *[[:space:]]* && $1 != *'"'* && $1 != *\\* && $1 != *"'"* ]]
}

valid_warp_line() {
    case $1 in
        full:*) valid_domain "${1#full:}" ;;
        geosite:*) [[ ${1#geosite:} =~ ^[A-Za-z0-9@!_-]+$ ]] ;;
        keyword:*) [[ ${1#keyword:} =~ ^[A-Za-z0-9._-]+$ ]] ;;
        regexp:*) [[ -n ${1#regexp:} && ${1#regexp:} != *[[:space:]]* ]] ;;
        *) valid_domain "$1" ;;
    esac
}

json_escape() {
    local value=${1//\\/\\\\}
    printf '%s' "${value//\"/\\\"}"
}

parse_yes_no() {
    case ${1,,} in
        y | yes | 1 | true | on) printf 'y' ;;
        n | no | 0 | false | off) printf 'n' ;;
        *) return 1 ;;
    esac
}

on_off() {
    if [ "$1" = y ]; then
        printf '开启'
    else
        printf '不开启'
    fi
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

first_match() {
    { grep -oE "$1" <<<"$2" || true; } | head -n 1
}

config_port() {
    { grep -oE '"port":[0-9]+' <<<"$1" || true; } | awk -F: 'NR == 1 {print $2}'
}

json_number() {
    { grep -oE "\"$2\":[0-9]+" <<<"$1" || true; } | awk -F: 'NR == 1 {print $2}'
}

jitter_value() {
    local center=$1 lo hi
    lo=$((center * (100 - FALLBACK_JITTER_PERCENT) / 100))
    hi=$((center * (100 + FALLBACK_JITTER_PERCENT) / 100))
    printf '%s' "$((lo + RANDOM % (hi - lo + 1)))"
}

shuffled_sni_pool() {
    local -a pool=("${SNI_POOL[@]}")
    local i j tmp
    for ((i = ${#pool[@]} - 1; i > 0; i--)); do
        j=$((RANDOM % (i + 1)))
        tmp=${pool[i]}
        pool[i]=${pool[j]}
        pool[j]=$tmp
    done
    printf '%s\n' "${pool[@]}"
}

image_id() {
    docker image inspect -f '{{.Id}}' "$XRAY_IMAGE" 2>/dev/null || true
}

image_xray_version() {
    docker run --rm "$XRAY_IMAGE" xray version 2>/dev/null | awk 'NR == 1 {print $2}' || true
}

decode_reserved() {
    { printf '%s' "$1" | base64 -d 2>/dev/null || true; } | od -An -tu1 | awk '{for (i = 1; i <= NF; i++) printf "%s%s", (n++ ? "," : ""), $i}'
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
    old_port=$(config_port "$flat")
    old_uuid=$(json_string "$flat" '"id":"[^"]*"')
    old_private_key=$(json_string "$flat" '"privateKey":"[^"]*"')
    old_short_id=$(json_string "$flat" '"shortIds":\["[^"]*"')
    info "发现已有配置 ${CONFIG_FILE}，按重装处理"

    if valid_domain "$old_sni"; then
        default_sni=$old_sni
        info "沿用已安装的 SNI 作为默认值: ${default_sni}"
    else
        info "已有配置中的 SNI 不合法 (值: ${old_sni:-空})，将从候选池重新挑选默认值"
    fi

    if valid_port "$old_port"; then
        default_port=$((10#$old_port))
        installed_port=$default_port
        info "沿用已安装的端口作为默认值: ${default_port}"
    else
        info "已有配置中的端口不合法 (值: ${old_port:-空})，默认值仍为 ${DEFAULT_PORT}"
    fi

    load_existing_warp "$flat"
    load_existing_fallback "$flat"
    load_existing_warp_list

    if valid_uuid "$old_uuid" && valid_key "$old_private_key" && valid_short_id "$old_short_id"; then
        reuse_credentials=true
        info "已有配置中的 UUID / 私钥 / ShortId 完整，本次复用，旧客户端无需更换密钥"
        return
    fi
    info "注意: 已有配置中的 UUID / 私钥 / ShortId 不完整 (UUID: $(credential_state "$old_uuid" valid_uuid), 私钥: $(credential_state "$old_private_key" valid_key), ShortId: $(credential_state "$old_short_id" valid_short_id))，将重新生成，旧客户端需重新导入"
}

load_existing_warp() {
    local flat=$1 addresses
    if [[ $flat != *'"protocol":"wireguard"'* ]]; then
        info "已有配置未开启 WARP，WARP 默认值为不开启"
        return
    fi
    default_warp=y
    addresses=$(first_match '"address":\[[^]]*\]' "$flat")
    warp_secret=$(json_string "$flat" '"secretKey":"[^"]*"')
    warp_v4=$(first_match '[0-9.]+/32' "$addresses")
    warp_v4=${warp_v4%/32}
    warp_v6=$(first_match '[0-9a-fA-F:]+/128' "$addresses")
    warp_v6=${warp_v6%/128}
    warp_reserved=$(first_match '[0-9]+,[0-9]+,[0-9]+' "$(first_match '"reserved":\[[0-9]+,[0-9]+,[0-9]+\]' "$flat")")
    warp_peer=$(json_string "$flat" '"publicKey":"[^"]*"')
    warp_endpoint=$(json_string "$flat" '"endpoint":"[^"]*"')
    if valid_wg_key "$warp_secret" && valid_ipv4 "$warp_v4" && valid_ipv6 "$warp_v6" && valid_reserved "$warp_reserved" && valid_wg_key "$warp_peer" && valid_endpoint "$warp_endpoint"; then
        reuse_warp=true
        info "已有配置开启了 WARP (地址: ${warp_v4}, ${warp_v6})，WARP 默认值沿用为开启，开启时复用该 WARP 账号"
        return
    fi
    info "注意: 已有配置开启了 WARP 但账号信息不完整 (私钥: $(credential_state "$warp_secret" valid_wg_key), IPv4: $(credential_state "$warp_v4" valid_ipv4), IPv6: $(credential_state "$warp_v6" valid_ipv6), reserved: $(credential_state "$warp_reserved" valid_reserved), 对端公钥: $(credential_state "$warp_peer" valid_wg_key), endpoint: $(credential_state "$warp_endpoint" valid_endpoint))，WARP 默认值沿用为开启，开启时重新注册"
    warp_secret=""
    warp_v4=""
    warp_v6=""
    warp_reserved=""
    warp_peer=""
    warp_endpoint=""
}

load_existing_warp_list() {
    if [ ! -f "$WARP_SYNC_FILE" ] && [ ! -f "$WARP_SYNC_STATE_FILE" ]; then
        info "未发现已安装的 WARP 订阅同步器，订阅 URL 默认值为 ${WARP_LIST_URL}"
        return
    fi
    local url
    url=$(head -n 1 "$WARP_SYNC_STATE_FILE" 2>/dev/null | tr -d '[:space:]' || true)
    if valid_url "$url"; then
        default_warp_list_url=$url
        info "沿用已安装的 WARP 订阅 URL 作为默认值: ${url}"
    else
        info "已安装的 WARP 订阅 URL 不合法 (值: ${url:-空})，默认值仍为 ${WARP_LIST_URL}"
    fi
    warp_list_reuse=true
}

collect_warp_list() {
    local raw=$1 line lineno=0 skipped=0 total=0 seen=$'\n'
    warp_custom_domains=""
    warp_custom_count=0
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        line=${line%$'\r'}
        line=${line#"${line%%[![:space:]]*}"}
        line=${line%"${line##*[![:space:]]}"}
        if [ -z "$line" ] || [[ $line == \#* ]]; then
            continue
        fi
        if ! valid_warp_line "$line"; then
            warp_list_skipped+="第 ${lineno} 行: ${line}"$'\n'
            skipped=$((skipped + 1))
            continue
        fi
        if [[ $seen == *$'\n'"$line"$'\n'* ]]; then
            continue
        fi
        if [ "$total" -ge "$WARP_SYNC_MAX_LINES" ]; then
            warp_list_truncated=true
            break
        fi
        seen+="$line"$'\n'
        warp_custom_domains+="$line"$'\n'
        total=$((total + 1))
    done <<<"$raw"
    warp_custom_count=$total
    warp_list_skipped_count=$skipped
}

fetch_warp_list() {
    local raw code=0
    mkdir -p "$CONFIG_DIR"
    warp_list_skipped=""
    warp_list_skipped_count=0
    warp_list_truncated=false
    raw=$(curl -fsS --max-time "$WARP_SYNC_FETCH_TIMEOUT" "$warp_list_url" 2>/dev/null) || code=$?
    if [ "$code" -ne 0 ]; then
        warp_list_status="拉取失败 (curl 退出码 ${code})"
        info "注意: WARP 订阅列表拉取失败 (${warp_list_url}, curl 退出码 ${code})，本次仅使用内置分流域名"
        return 1
    fi
    collect_warp_list "$raw"
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        info "订阅列表非法行已跳过 (${line})"
    done <<<"$warp_list_skipped"
    if [ "$warp_list_truncated" = true ]; then
        info "订阅列表超过 ${WARP_SYNC_MAX_LINES} 条上限，其余行忽略"
    fi
    info "订阅列表解析完成 (有效 ${warp_custom_count} 条, 跳过非法 ${warp_list_skipped_count} 行)"
    printf '%s' "$warp_custom_domains" >"$WARP_LIST_FILE"
    warp_list_status="已生效 (${warp_custom_count} 条自定义域名)"
}

load_existing_fallback() {
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
        info "已有配置未开启回落限速，回落限速默认值为不开启"
        return
    fi
    default_fallback=y
    if [ -n "$fallback_up_after" ] && [ -n "$fallback_up_burst" ] && [ -n "$fallback_down_after" ] && [ -n "$fallback_down_burst" ] && [ "${fallback_up_rate:-0}" -gt 0 ] && [ "${fallback_down_rate:-0}" -gt 0 ]; then
        reuse_fallback=true
        info "已有配置开启了回落限速 (上行 ${fallback_up_after}/${fallback_up_rate}/${fallback_up_burst}, 下行 ${fallback_down_after}/${fallback_down_rate}/${fallback_down_burst})，默认值沿用为开启，开启时复用这些值"
        return
    fi
    info "注意: 已有配置的回落限速参数不完整 (上行: ${fallback_up_after:-空}/${fallback_up_rate:-空}/${fallback_up_burst:-空}, 下行: ${fallback_down_after:-空}/${fallback_down_rate:-空}/${fallback_down_burst:-空})，默认值沿用为开启，开启时重新随机生成"
    fallback_up_after=""
    fallback_up_rate=""
    fallback_up_burst=""
    fallback_down_after=""
    fallback_down_rate=""
    fallback_down_burst=""
}

pick_default_sni() {
    local candidate code
    step "正在从候选池挑选伪装目标 (共 ${#SNI_POOL[@]} 个，随机顺序逐个检测 TLS 1.3)..."
    while read -r candidate; do
        code=0
        curl -s -o /dev/null --max-time "$SNI_PROBE_TIMEOUT" --tlsv1.3 "https://${candidate}" || code=$?
        if [ "$code" -eq 0 ]; then
            default_sni=$candidate
            info "候选 ${candidate} 支持 TLS 1.3，选为默认伪装目标"
            return
        fi
        info "候选 ${candidate} 检测未通过 (curl 退出码 ${code})，尝试下一个"
    done < <(shuffled_sni_pool)
    default_sni=$(shuffled_sni_pool | head -n 1)
    info "注意: 候选池 ${#SNI_POOL[@]} 个域名全部检测未通过，仍取 ${default_sni} 作为默认值；REALITY 要求伪装站能从本机访问且支持 TLS 1.3，建议用 XRAY_SNI 指定一个可用域名"
}

choose_sni() {
    if [ -n "${XRAY_SNI:-}" ]; then
        valid_domain "$XRAY_SNI" || fail "环境变量 XRAY_SNI=${XRAY_SNI} 不是合法域名 (示例: ${SNI_POOL[0]})"
        sni=$XRAY_SNI
        info "伪装目标 (dest/SNI): ${sni} (来自环境变量 XRAY_SNI)"
        return
    fi
    if [ -z "$default_sni" ]; then
        pick_default_sni
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

read_yes_no() {
    local question=$1 default=$2 hint="y/N" answer
    if [ "$default" = y ]; then
        hint="Y/n"
    fi
    while true; do
        read -r -p "${question} [${hint}]: " answer </dev/tty || answer=""
        answer=${answer:-$default}
        if parse_yes_no "$answer"; then
            return
        fi
        info "${answer} 不合法，请输入 y 或 n" >&2
    done
}

choose_bbr() {
    if [ -n "${XRAY_BBR:-}" ]; then
        bbr_choice=$(parse_yes_no "$XRAY_BBR") || fail "环境变量 XRAY_BBR=${XRAY_BBR} 不合法，需为 y 或 n"
        info "BBR 加速: $(on_off "$bbr_choice") (来自环境变量 XRAY_BBR)"
        return
    fi
    if ! has_tty; then
        bbr_choice=y
        info "BBR 加速: 开启 (无交互终端且未设置 XRAY_BBR，取默认值)"
        return
    fi
    bbr_choice=$(read_yes_no "是否开启 BBR 加速" y)
    info "BBR 加速: $(on_off "$bbr_choice")"
}

choose_warp() {
    if [ -n "${XRAY_WARP:-}" ]; then
        warp_choice=$(parse_yes_no "$XRAY_WARP") || fail "环境变量 XRAY_WARP=${XRAY_WARP} 不合法，需为 y 或 n"
        info "WARP 分流: $(on_off "$warp_choice") (来自环境变量 XRAY_WARP)"
        return
    fi
    if ! has_tty; then
        warp_choice=$default_warp
        info "WARP 分流: $(on_off "$warp_choice") (无交互终端且未设置 XRAY_WARP，取默认值)"
        return
    fi
    warp_choice=$(read_yes_no "是否开启 Cloudflare WARP 分流 (AI 服务、Netflix、Disney+ 经 WARP 出站)" "$default_warp")
    info "WARP 分流: $(on_off "$warp_choice")"
}

choose_warp_list_url() {
    if [ "$warp_list_reuse" = true ] && [ -z "${XRAY_WARP_LIST:-}" ]; then
        warp_list_url=$default_warp_list_url
        info "WARP 订阅列表: ${warp_list_url:-不启用} (沿用已安装的订阅)"
        return
    fi
    if [ -n "${XRAY_WARP_LIST:-}" ]; then
        valid_url "$XRAY_WARP_LIST" || fail "环境变量 XRAY_WARP_LIST=${XRAY_WARP_LIST} 不是合法的 https URL (不能含空格/引号/反斜杠)"
        warp_list_url=$XRAY_WARP_LIST
        info "WARP 订阅列表: ${warp_list_url} (来自环境变量 XRAY_WARP_LIST)"
        return
    fi
    if ! has_tty; then
        warp_list_url=$default_warp_list_url
        info "WARP 订阅列表: ${warp_list_url} (无交互终端且未设置 XRAY_WARP_LIST，取默认值)"
        return
    fi
    while true; do
        read -r -p "WARP 订阅列表 URL (每天自动拉取, 留空 = 默认列表, 输入 n = 不启用): " warp_list_url </dev/tty || warp_list_url=""
        if [ -z "$warp_list_url" ]; then
            warp_list_url=$default_warp_list_url
            info "WARP 订阅列表: ${warp_list_url} (默认列表)"
            return
        fi
        if [ "$warp_list_url" = n ]; then
            warp_list_url=""
            info "WARP 订阅列表: 不启用 (只用内置分流域名)"
            return
        fi
        valid_url "$warp_list_url" && break
        info "${warp_list_url} 不是合法的 https URL (不能含空格/引号/反斜杠)，请重新输入"
    done
    info "WARP 订阅列表: ${warp_list_url}"
}

choose_fallback() {
    if [ -n "${XRAY_FALLBACK_LIMIT:-}" ]; then
        fallback_choice=$(parse_yes_no "$XRAY_FALLBACK_LIMIT") || fail "环境变量 XRAY_FALLBACK_LIMIT=${XRAY_FALLBACK_LIMIT} 不合法，需为 y 或 n"
        info "回落限速: $(on_off "$fallback_choice") (来自环境变量 XRAY_FALLBACK_LIMIT)"
        return
    fi
    if ! has_tty; then
        fallback_choice=$default_fallback
        info "回落限速: $(on_off "$fallback_choice") (无交互终端且未设置 XRAY_FALLBACK_LIMIT，取默认值)"
        return
    fi
    fallback_choice=$(read_yes_no "是否开启 REALITY 回落限速 (限制认证失败的偷跑流量，本身也是一种特征，伪装站与本机同 ASN 时无需开启)" "$default_fallback")
    info "回落限速: $(on_off "$fallback_choice")"
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

check_sni_not_self() {
    local resolved local_addrs addr
    if ! command -v getent >/dev/null 2>&1; then
        info "未找到 getent 命令，跳过伪装站是否指向本机的检查"
        return
    fi
    resolved=$(getent ahosts "$sni" 2>/dev/null | awk '{print $1}' | sort -u || true)
    if [ -z "$resolved" ]; then
        info "伪装站 ${sni} 暂时解析不到 IP，跳过是否指向本机的检查"
        return
    fi
    local_addrs=$(ip -o addr show 2>/dev/null | awk '{split($4, a, "/"); print a[1]}' || true)
    for addr in $resolved; do
        if [[ $addr == 127.* || $addr == ::1 || $addr == 0.0.0.0 || $addr == "$server_ip" ]] || grep -qxF "$addr" <<<"$local_addrs"; then
            fail "伪装目标 ${sni} 解析到本机地址 ${addr}，REALITY 会把连接转发给自己，形成无限自连并耗尽连接数和内存；请换成第三方网站 (如 ${SNI_POOL[0]})"
        fi
    done
    info "伪装站 ${sni} 解析到 $(tr '\n' ' ' <<<"$resolved")未指向本机"
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
    if command -v systemctl >/dev/null 2>&1 && [ "$(systemctl is-enabled docker 2>/dev/null || true)" = disabled ]; then
        info "注意: Docker 未设置开机自启，服务器重启后 Xray 不会自动恢复，可执行 systemctl enable docker"
    fi
}

install_docker() {
    local os_id package_manager
    step "未检测到 Docker，正在通过 get.docker.com 安装..."
    tmp_get_docker=$(mktemp)
    curl -fsSL https://get.docker.com -o "$tmp_get_docker" || fail "下载 get.docker.com 安装脚本失败"
    if sh "$tmp_get_docker" </dev/null; then
        return
    fi
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

ensure_image() {
    if docker image inspect "$XRAY_IMAGE" >/dev/null 2>&1; then
        info "镜像 ${XRAY_IMAGE} 已存在，跳过拉取"
    else
        step "正在拉取镜像 ${XRAY_IMAGE}..."
        docker pull "$XRAY_IMAGE" || fail "拉取镜像 ${XRAY_IMAGE} 失败"
    fi
    info "Xray 版本: $(image_xray_version)"
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

register_warp() {
    local output wg_private wg_public tos body response http_code curl_code=0 addresses client_id
    if ! output=$(docker run --rm "$XRAY_IMAGE" xray wg 2>&1); then
        warp_failure="执行 xray wg 生成 WireGuard 密钥失败"
        return 1
    fi
    wg_private=$(key_from_output private "$output")
    wg_public=$(key_from_output public "$output")
    if ! valid_wg_key "$wg_private" || ! valid_wg_key "$wg_public"; then
        warp_failure="无法解析 xray wg 的输出 (输出字段: $(output_labels "$output"))"
        return 1
    fi
    tos=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
    body="{\"fcm_token\":\"\",\"install_id\":\"\",\"key\":\"${wg_public}\",\"locale\":\"en_US\",\"model\":\"PC\",\"tos\":\"${tos}\",\"serial_number\":\"\",\"os_version\":\"16.0.0\",\"key_type\":\"curve25519\",\"tunnel_type\":\"wireguard\"}"
    response=$(curl -sS --max-time 20 -X POST "$WARP_API" \
        -H "User-Agent: ${WARP_USER_AGENT}" \
        -H "CF-Client-Version: ${WARP_CLIENT_VERSION}" \
        -H "Content-Type: application/json; charset=UTF-8" \
        -d "$body" -w $'\n%{http_code}' 2>/dev/null) || curl_code=$?
    if [ "$curl_code" -ne 0 ]; then
        warp_failure="调用 WARP 注册接口失败 (curl 退出码 ${curl_code})"
        return 1
    fi
    http_code=${response##*$'\n'}
    response=$(tr -d ' \t\r\n' <<<"${response%$'\n'*}")
    if [ "$http_code" != 200 ]; then
        warp_failure="WARP 注册接口返回 HTTP ${http_code} (响应: ${response:0:160})"
        return 1
    fi
    addresses=$(first_match '"addresses":\{[^}]*\}' "$response")
    warp_v4=$(json_string "$addresses" '"v4":"[^"]*"')
    warp_v6=$(json_string "$addresses" '"v6":"[^"]*"')
    client_id=$(json_string "$response" '"client_id":"[^"]*"')
    warp_reserved=$(decode_reserved "$client_id")
    warp_peer=$(json_string "$response" '"public_key":"[^"]*"')
    warp_endpoint=$(json_string "$response" '"host":"[^"]*"')
    warp_secret=$wg_private
    if ! valid_ipv4 "$warp_v4" || ! valid_ipv6 "$warp_v6" || ! valid_reserved "$warp_reserved" || ! valid_wg_key "$warp_peer" || ! valid_endpoint "$warp_endpoint"; then
        warp_failure="无法解析 WARP 注册结果 (IPv4: ${warp_v4:-空}, IPv6: ${warp_v6:-空}, client_id: ${client_id:-空} -> reserved: ${warp_reserved:-空}, 对端公钥: ${warp_peer:-空}, endpoint: ${warp_endpoint:-空})"
        return 1
    fi
    info "WARP 注册成功 (地址: ${warp_v4}, ${warp_v6}, reserved: ${warp_reserved}, endpoint: ${warp_endpoint})"
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

render_warp_routing() {
    cat <<EOF
,
  "routing": {
    "rules": [
      {
        "type": "field",
        "domain": [
$(render_warp_domains)
        ],
        "outboundTag": "warp"
      }
    ]
  }
EOF
}

render_warp_sync_script() {
    local script
    script=$(cat <<'WARP_SYNC_EOF'
#!/usr/bin/env bash
set -euo pipefail

readonly XRAY_IMAGE="teddysun/xray"
readonly CONTAINER_NAME="xray-reality"
readonly CONFIG_DIR="/etc/xray"
readonly CONFIG_FILE="${CONFIG_DIR}/config.json"
readonly LIST_FILE="${CONFIG_DIR}/warp-domains.txt"
readonly STATE_FILE="${CONFIG_DIR}/warp-sync-state"
readonly STATE_TMP="${CONFIG_DIR}/warp-sync-state.tmp"
readonly CONFIG_TMP="${CONFIG_DIR}/config.sync.json"
readonly LOCK_DIR="${CONFIG_DIR}/warp-sync.lock"
readonly FETCH_TIMEOUT=20
readonly MAX_LINES=1000
readonly LOCK_STALE_SECONDS=600
readonly LOG_MAX_SIZE="10m"
readonly LOG_MAX_FILE="3"
readonly -a BUILTIN_DOMAINS=('geosite:category-ai-!cn' 'geosite:netflix' 'geosite:disney')
readonly LIST_URL="__WARP_LIST_URL__"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        return
    fi
    local age now mtime
    now=$(date +%s)
    mtime=$(stat -c %Y "$LOCK_DIR" 2>/dev/null || echo "$now")
    age=$((now - mtime))
    if [ "$age" -lt "$LOCK_STALE_SECONDS" ]; then
        log "skip, 已有同步在运行 (锁龄 ${age}s < ${LOCK_STALE_SECONDS}s)"
        exit 0
    fi
    log "接管过期锁 (锁龄 ${age}s >= ${LOCK_STALE_SECONDS}s)"
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null || { log "skip, 抢锁失败, 另一同步刚接管"; exit 0; }
}

valid_domain() {
    local re='^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z][A-Za-z0-9-]{0,61}[A-Za-z0-9]$'
    [ "${#1}" -le 253 ] && [[ $1 =~ $re ]]
}

valid_warp_line() {
    case $1 in
        full:*) valid_domain "${1#full:}" ;;
        geosite:*) [[ ${1#geosite:} =~ ^[A-Za-z0-9@!_-]+$ ]] ;;
        keyword:*) [[ ${1#keyword:} =~ ^[A-Za-z0-9._-]+$ ]] ;;
        regexp:*) [[ -n ${1#regexp:} && ${1#regexp:} != *[[:space:]]* ]] ;;
        *) valid_domain "$1" ;;
    esac
}

json_escape() {
    local value=${1//\\/\\\\}
    printf '%s' "${value//\"/\\\"}"
}

collect_list() {
    local raw=$1 line lineno=0 skipped=0 total=0 seen=$'\n'
    list_domains=""
    list_count=0
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        line=${line%$'\r'}
        line=${line#"${line%%[![:space:]]*}"}
        line=${line%"${line##*[![:space:]]}"}
        if [ -z "$line" ] || [[ $line == \#* ]]; then
            continue
        fi
        if ! valid_warp_line "$line"; then
            log "skip, 非法行不写入规则, 第 ${lineno} 行: ${line}"
            skipped=$((skipped + 1))
            continue
        fi
        if [[ $seen == *$'\n'"$line"$'\n'* ]]; then
            continue
        fi
        if [ "$total" -ge "$MAX_LINES" ]; then
            log "skip, 超过 ${MAX_LINES} 条上限, 其余行忽略"
            break
        fi
        seen+="$line"$'\n'
        list_domains+="$line"$'\n'
        total=$((total + 1))
    done <<<"$raw"
    list_count=$total
    log "done, 列表解析完成, 有效 ${total} 条, 跳过非法 ${skipped} 行"
}

render_domains() {
    printf '          "%s"' "${BUILTIN_DOMAINS[0]}"
    local domain
    for domain in "${BUILTIN_DOMAINS[@]:1}"; do
        printf ',\n          "%s"' "$domain"
    done
    [ -n "$list_domains" ] || return 0
    while IFS= read -r domain; do
        [ -n "$domain" ] || continue
        printf ',\n          "%s"' "$(json_escape "$domain")"
    done <<<"$list_domains"
}

if [ "$(id -u)" -ne 0 ]; then
    log "fail, 需要 root 运行 (当前 uid: $(id -u))"
    exit 1
fi
if [ ! -f "$CONFIG_FILE" ]; then
    log "fail, 缺少节点配置 ${CONFIG_FILE}, 请先执行安装"
    exit 1
fi
if ! grep -q '"protocol": *"wireguard"' "$CONFIG_FILE"; then
    log "skip, 现有配置未开启 WARP, 不同步 (重开 WARP 请重跑安装)"
    exit 0
fi
acquire_lock
trap 'rm -rf "$LOCK_DIR"; rm -f "$CONFIG_TMP" "$STATE_TMP"' EXIT

raw=$(curl -fsS --max-time "$FETCH_TIMEOUT" "$LIST_URL" 2>/dev/null) || {
    log "fail, 订阅列表拉取失败 (curl 退出码 $?, url: ${LIST_URL}), 保持现有配置"
    exit 0
}
list_domains=""
collect_list "$raw"

old_hash=""
if [ -f "$STATE_FILE" ]; then
    old_hash=$(sed -n 2p "$STATE_FILE" | tr -d '[:space:]')
fi
new_hash=$(printf '%s' "$list_domains" | sha256sum | awk '{print $1}')
if [ "$new_hash" = "$old_hash" ]; then
    log "done, 订阅列表无变化, 不重建容器 (hash: ${new_hash:0:12})"
    exit 0
fi
if ! docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    log "fail, 容器 ${CONTAINER_NAME} 不存在, 无法应用, 请先执行安装"
    exit 0
fi
if ! grep -q '^  "routing": {$' "$CONFIG_FILE"; then
    log "fail, 配置里找不到脚本生成的 routing 段 (可能被手工改过), 保持现有配置"
    exit 0
fi

sed '/^  "routing": {$/,$d' "$CONFIG_FILE" >"$CONFIG_TMP"
cat >>"$CONFIG_TMP" <<ROUTING_EOF
  "routing": {
    "rules": [
      {
        "type": "field",
        "domain": [
$(render_domains)
        ],
        "outboundTag": "warp"
      }
    ]
  }
}
ROUTING_EOF

if ! output=$(docker run --rm -v "${CONFIG_DIR}:${CONFIG_DIR}" "$XRAY_IMAGE" xray run -test -c "$CONFIG_TMP" 2>&1); then
    log "fail, 新配置未通过 xray run -test, 保持现有配置: $(printf '%s' "$output" | tail -n 1)"
    exit 0
fi

mv "$CONFIG_FILE" "${CONFIG_FILE}.before-sync"
mv -f "$CONFIG_TMP" "$CONFIG_FILE"
docker rm -f -v "$CONTAINER_NAME" >/dev/null
if ! docker run -d \
    --name "$CONTAINER_NAME" \
    --restart always \
    --net host \
    --log-driver json-file \
    --log-opt max-size="$LOG_MAX_SIZE" \
    --log-opt max-file="$LOG_MAX_FILE" \
    -v "${CONFIG_DIR}:${CONFIG_DIR}" \
    "$XRAY_IMAGE" >/dev/null; then
    mv -f "${CONFIG_FILE}.before-sync" "$CONFIG_FILE"
    docker run -d --name "$CONTAINER_NAME" --restart always --net host --log-driver json-file --log-opt max-size="$LOG_MAX_SIZE" --log-opt max-file="$LOG_MAX_FILE" -v "${CONFIG_DIR}:${CONFIG_DIR}" "$XRAY_IMAGE" >/dev/null 2>&1 || true
    log "fail, 新容器启动失败, 已按旧配置回滚容器"
    exit 1
fi
sleep 2
status=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo missing)
if [ "$status" != running ]; then
    mv -f "${CONFIG_FILE}.before-sync" "$CONFIG_FILE"
    docker rm -f -v "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker run -d --name "$CONTAINER_NAME" --restart always --net host --log-driver json-file --log-opt max-size="$LOG_MAX_SIZE" --log-opt max-file="$LOG_MAX_FILE" -v "${CONFIG_DIR}:${CONFIG_DIR}" "$XRAY_IMAGE" >/dev/null 2>&1 || true
    log "fail, 新容器未稳定运行 (状态: ${status}), 已按旧配置回滚容器"
    exit 1
fi
rm -f "${CONFIG_FILE}.before-sync"
{ printf '%s\n%s\n' "$LIST_URL" "$new_hash"; } >"$STATE_TMP"
mv -f "$STATE_TMP" "$STATE_FILE"
printf '%s' "$list_domains" >"$LIST_FILE"
log "done, 订阅已应用并重建容器 (自定义规则 ${list_count} 条, hash: ${new_hash:0:12})"
WARP_SYNC_EOF
)
    printf '%s\n' "${script//__WARP_LIST_URL__/$warp_list_url}"
}

remove_warp_sync() {
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
    rm -f "$WARP_SYNC_FILE" "$WARP_SYNC_STATE_FILE" "$WARP_LIST_FILE"
    rm -rf "${CONFIG_DIR}/warp-sync.lock"
}

setup_warp_sync() {
    remove_warp_sync
    if [ -z "$warp_list_url" ]; then
        warp_sync_status="不启用"
        info "WARP 订阅同步: 未启用 (只用内置分流域名)"
        return
    fi
    tmp_warp_sync_script=$(mktemp)
    render_warp_sync_script >"$tmp_warp_sync_script"
    chmod 700 "$tmp_warp_sync_script"
    mv -f "$tmp_warp_sync_script" "$WARP_SYNC_FILE"
    tmp_warp_sync_script=""
    { printf '%s\n' "$warp_list_url"; } >"$WARP_SYNC_STATE_FILE"
    if command -v systemctl >/dev/null 2>&1; then
        cat >"/etc/systemd/system/${WARP_SYNC_UNIT}.service" <<EOF
[Unit]
Description=Xray WARP domain list sync

[Service]
Type=oneshot
ExecStart=${WARP_SYNC_FILE}
EOF
        cat >"/etc/systemd/system/${WARP_SYNC_UNIT}.timer" <<EOF
[Unit]
Description=Daily Xray WARP domain list sync

[Timer]
OnCalendar=${WARP_SYNC_INTERVAL}
Persistent=true
RandomizedDelaySec=${WARP_SYNC_JITTER_SECONDS}

[Install]
WantedBy=timers.target
EOF
        if systemctl daemon-reload && systemctl enable --now "${WARP_SYNC_UNIT}.timer" >/dev/null 2>&1; then
            warp_sync_status="已启用 (systemd timer ${WARP_SYNC_UNIT}.timer, 每天一次)"
            info "WARP 订阅同步: ${warp_sync_status}；改完 GitHub 上的列表最迟一天生效，想立即生效执行 ${WARP_SYNC_FILE}"
            return
        fi
        info "注意: systemd timer 启用失败，改用 cron"
    fi
    if command -v crontab >/dev/null 2>&1; then
        local current minute hour
        current=$(crontab -l 2>/dev/null || true)
        minute=$((RANDOM % 60))
        hour=$((RANDOM % 24))
        { grep -vF "$WARP_SYNC_CRON_MARK" <<<"$current" || true; printf '%s %s * * * %s %s\n' "$minute" "$hour" "$WARP_SYNC_FILE" "$WARP_SYNC_CRON_MARK"; } | crontab - || fail "写入 root crontab 失败，无法启用 WARP 订阅同步"
        warp_sync_status="已启用 (cron 每天 ${hour}:$(printf '%02d' "$minute") 一次)"
        info "WARP 订阅同步: ${warp_sync_status}；想立即生效执行 ${WARP_SYNC_FILE}"
        return
    fi
    warp_sync_status="未启用 (系统无 systemctl 也无 crontab)"
    info "注意: 系统既无 systemctl 也无 crontab，订阅同步无法定时运行；可手动执行 ${WARP_SYNC_FILE} 拉取一次"
}

render_warp_check_config() {
    cat <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": $1,
      "protocol": "socks",
      "settings": {
        "udp": false
      }
    }
  ],
  "outbounds": [
$(render_warp_outbound)
  ]
}
EOF
}

pick_free_port() {
    local p
    for ((p = 20808; p <= 20908; p++)); do
        if [ -z "$(ss -Htln "sport = :${p}" 2>/dev/null || true)" ]; then
            printf '%s' "$p"
            return
        fi
    done
    return 1
}

check_warp() {
    local check_port attempt trace warp_flag="" egress=""
    if ! check_port=$(pick_free_port); then
        warp_failure="找不到空闲的本地端口 (20808-20908) 用于 WARP 连通性检测"
        return 1
    fi
    warp_check_dir=$(mktemp -d)
    (umask 077 && render_warp_check_config "$check_port" >"${warp_check_dir}/config.json")
    docker rm -f -v "$WARP_CHECK_CONTAINER" >/dev/null 2>&1 || true
    if ! docker run -d --name "$WARP_CHECK_CONTAINER" --net host -v "${warp_check_dir}:/etc/xray:ro" "$XRAY_IMAGE" >/dev/null; then
        warp_failure="启动 WARP 检测容器 ${WARP_CHECK_CONTAINER} 失败"
        return 1
    fi
    warp_check_started=true
    for ((attempt = 1; attempt <= 3; attempt++)); do
        sleep 2
        trace=$(curl -s --max-time 10 -x "socks5h://127.0.0.1:${check_port}" "$WARP_CHECK_URL" 2>/dev/null || true)
        warp_flag=$(awk -F= '$1 == "warp" {print $2}' <<<"$trace")
        egress=$(awk -F= '$1 == "ip" {print $2}' <<<"$trace")
        if [ "$warp_flag" = on ] || [ "$warp_flag" = plus ]; then
            info "WARP 连通性检测通过 (第 ${attempt} 次, WARP 出口 IP: ${egress}, warp=${warp_flag})"
            break
        fi
        info "WARP 连通性检测第 ${attempt} 次未通过 (warp=${warp_flag:-无响应}, 出口 IP: ${egress:-无})"
    done
    if [ "$warp_flag" != on ] && [ "$warp_flag" != plus ]; then
        docker logs --tail 3 "$WARP_CHECK_CONTAINER" >&2 || true
    fi
    docker rm -f -v "$WARP_CHECK_CONTAINER" >/dev/null 2>&1 || true
    warp_check_started=false
    rm -rf "$warp_check_dir"
    warp_check_dir=""
    if [ "$warp_flag" = on ] || [ "$warp_flag" = plus ]; then
        return 0
    fi
    warp_failure="WARP 连通性检测 3 次均未通过 (经 WARP 访问 ${WARP_CHECK_URL} 未得到 warp=on，上面是检测容器日志)"
    return 1
}

skip_warp() {
    warp_enabled=false
    warp_list_url=""
    warp_list_status=""
    warp_status="未开启 (开启失败已跳过: ${warp_failure})"
    info "注意: ${warp_failure}，本次跳过 WARP，Reality 照常安装"
}

setup_warp() {
    if [ "$warp_choice" != y ]; then
        warp_list_url=""
        warp_status="未开启"
        if [ "$default_warp" = y ]; then
            info "跳过 WARP: 本次选择不开启，已安装的 WARP 出站将从配置中移除"
        else
            info "跳过 WARP: 未选择开启"
        fi
        return
    fi
    choose_warp_list_url
    if [ "$reuse_warp" = true ]; then
        info "复用已有 WARP 账号 (地址: ${warp_v4}, ${warp_v6})，不重新注册"
    else
        step "正在注册 Cloudflare WARP 账号..."
        if ! register_warp; then
            skip_warp
            return
        fi
    fi
    if ! check_warp; then
        skip_warp
        return
    fi
    if [ -n "$warp_list_url" ]; then
        fetch_warp_list || true
    fi
    warp_enabled=true
    warp_status="已开启 (AI 服务 / Netflix / Disney+ 经 WARP 出站，IPv4 优先)"
    if [ -n "$warp_list_url" ]; then
        warp_status+="，订阅 ${warp_list_url} (${warp_list_status})"
    else
        warp_list_status="不启用 (只用内置分流域名)"
    fi
}

setup_fallback() {
    if [ "$fallback_choice" != y ]; then
        fallback_status="未开启"
        if [ "$default_fallback" = y ]; then
            info "跳过回落限速: 本次选择不开启，已安装的回落限速参数将从配置中移除"
        else
            info "跳过回落限速: 未选择开启 (伪装站与本机同 ASN 时本就不需要)"
        fi
        return
    fi
    if [ "$reuse_fallback" = true ]; then
        info "复用已有回落限速参数 (上行 ${fallback_up_after}/${fallback_up_rate}/${fallback_up_burst}, 下行 ${fallback_down_after}/${fallback_down_rate}/${fallback_down_burst})，不重新随机"
    else
        fallback_up_after=$(jitter_value "$FALLBACK_AFTER_BYTES_CENTER")
        fallback_up_rate=$(jitter_value "$FALLBACK_BYTES_PER_SEC_CENTER")
        fallback_up_burst=$(jitter_value "$FALLBACK_BURST_BYTES_PER_SEC_CENTER")
        fallback_down_after=$(jitter_value "$FALLBACK_AFTER_BYTES_CENTER")
        fallback_down_rate=$(jitter_value "$FALLBACK_BYTES_PER_SEC_CENTER")
        fallback_down_burst=$(jitter_value "$FALLBACK_BURST_BYTES_PER_SEC_CENTER")
        info "回落限速参数已随机生成 (以官方示例值为中心 ±${FALLBACK_JITTER_PERCENT}%，上行 ${fallback_up_after}/${fallback_up_rate}/${fallback_up_burst}, 下行 ${fallback_down_after}/${fallback_down_rate}/${fallback_down_burst})"
    fi
    fallback_enabled=true
    fallback_status="已开启 (上行 ${fallback_up_after}/${fallback_up_rate}/${fallback_up_burst}, 下行 ${fallback_down_after}/${fallback_down_rate}/${fallback_down_burst}，仅限制认证失败的连接)"
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

render_config() {
    local warp_outbound="" warp_routing="" fallback_limits=""
    if [ "$warp_enabled" = true ]; then
        warp_outbound=$',\n'"$(render_warp_outbound)"
        warp_routing=$(render_warp_routing)
    fi
    if [ "$fallback_enabled" = true ]; then
        fallback_limits=$(render_fallback_limits)
    fi
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
          ]${fallback_limits}
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
    }${warp_outbound}
  ]${warp_routing}
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
    if [ "$fallback_enabled" = true ]; then
        info "回落限速已写入配置 (仅限制认证失败的连接，已通过认证的客户端不受影响)"
    fi
}

remove_old_container() {
    if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
        docker rm -f -v "$CONTAINER_NAME" >/dev/null
        info "已移除旧容器 ${CONTAINER_NAME}"
    fi
}

run_container() {
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart always \
        --net host \
        --log-driver json-file \
        --log-opt max-size="$LOG_MAX_SIZE" \
        --log-opt max-file="$LOG_MAX_FILE" \
        -v "${CONFIG_DIR}:${CONFIG_DIR}" \
        "$XRAY_IMAGE" >/dev/null || fail "启动容器 ${CONTAINER_NAME} 失败"
    info "容器日志按 json-file 轮转，单文件上限 ${LOG_MAX_SIZE}，最多保留 ${LOG_MAX_FILE} 份"
}

start_container() {
    remove_old_container
    mv -f "$tmp_config" "$CONFIG_FILE"
    tmp_config=""
    step "正在启动 Xray Reality..."
    run_container
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
            remind_old_port_rule ufw "$status"
            return
        fi
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        if firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null && firewall-cmd --reload >/dev/null; then
            info "firewalld 已启用，已放行 TCP ${port}"
        else
            info "注意: firewalld 放行 TCP ${port} 失败，请手动执行 firewall-cmd --permanent --add-port=${port}/tcp && firewall-cmd --reload"
        fi
        remind_old_port_rule firewalld ""
        return
    fi
    info "未检测到启用中的 ufw / firewalld，跳过系统防火墙放行；如云厂商有安全组，请自行放行 TCP ${port}"
}

remind_old_port_rule() {
    if ! valid_port "$installed_port" || [ "$installed_port" = "$port" ]; then
        return
    fi
    if [ "$1" = ufw ]; then
        if grep -qE "^${installed_port}/tcp[[:space:]]" <<<"$2"; then
            info "提示: 端口已从 ${installed_port} 改为 ${port}，旧端口的 ufw 放行规则保留未删；确认不再需要可执行: ufw delete allow ${installed_port}/tcp"
        fi
        return
    fi
    if firewall-cmd --permanent --query-port="${installed_port}/tcp" >/dev/null 2>&1; then
        info "提示: 端口已从 ${installed_port} 改为 ${port}，旧端口的 firewalld 放行规则保留未删；确认不再需要可执行: firewall-cmd --permanent --remove-port=${installed_port}/tcp && firewall-cmd --reload"
    fi
}

enable_bbr() {
    local kernel available old_cc old_qdisc new_cc new_qdisc lines persist_note
    kernel=$(uname -r)
    if ! command -v sysctl >/dev/null 2>&1; then
        bbr_status="未开启 (缺少 sysctl 命令)"
        info "提示: 未找到 sysctl 命令，跳过 BBR"
        return
    fi
    old_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 未知)
    old_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo 未知)
    if [ "$bbr_choice" != y ]; then
        bbr_status="按选择跳过，未改动 (当前拥塞控制 ${old_cc}, 队列算法 ${old_qdisc})"
        info "跳过 BBR: 你选择不开启，保持现状 (拥塞控制: ${old_cc}, 队列算法: ${old_qdisc})"
        return
    fi
    available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)
    if [[ " ${available} " != *" bbr "* ]] && command -v modprobe >/dev/null 2>&1 && modprobe tcp_bbr 2>/dev/null; then
        available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)
        info "已加载内核模块 tcp_bbr (可用算法: ${available})"
    fi
    if [[ " ${available} " != *" bbr "* ]]; then
        bbr_status="未开启 (内核 ${kernel} 不支持)"
        info "提示: 内核 ${kernel} 不支持 BBR (可用算法: ${available:-无法读取})，跳过 BBR，不升级内核"
        return
    fi
    if ! sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1; then
        bbr_status="未开启 (无法修改内核参数)"
        info "提示: 无法设置 net.ipv4.tcp_congestion_control=bbr (多见于 OpenVZ/LXC 等容器 VPS，内核参数由宿主机控制)，跳过 BBR"
        return
    fi
    mkdir -p "$(dirname "$BBR_SYSCTL_FILE")" 2>/dev/null || true
    if sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1; then
        lines=$'net.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr'
    else
        info "提示: 无法设置 net.core.default_qdisc=fq，队列算法保持 ${old_qdisc}；4.13 及以上内核的 BBR 不依赖 fq"
        lines="net.ipv4.tcp_congestion_control = bbr"
    fi
    persist_note="已写入 ${BBR_SYSCTL_FILE}，重启后保持"
    if ! printf '%s\n' "$lines" >"$BBR_SYSCTL_FILE"; then
        persist_note="注意: 写入 ${BBR_SYSCTL_FILE} 失败，本次已生效但重启后不会保持"
    fi
    new_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 未知)
    new_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo 未知)
    bbr_status="已开启 (拥塞控制 ${new_cc}, 队列算法 ${new_qdisc})"
    info "BBR 已开启 (拥塞控制: ${old_cc} -> ${new_cc}, 队列算法: ${old_qdisc} -> ${new_qdisc})，${persist_note}"
}

render_clash_config() {
    cat <<EOF
proxies:
  - name: Reality-${server_ip}
    type: vless
    server: ${server_ip}
    port: ${port}
    uuid: ${uuid}
    flow: ${FLOW}
    network: tcp
    tls: true
    udp: true
    client-fingerprint: ${FINGERPRINT}
    servername: ${sni}
    reality-opts:
      public-key: ${public_key}
      short-id: ${short_id}
EOF
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
BBR 加速:    ${hl}${bbr_status}${off}
WARP 分流:   ${hl}${warp_status}${off}
WARP 订阅:   ${hl}${warp_sync_status}${off}
回落限速:    ${hl}${fallback_status}${off}
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
    (umask 077 && render_clash_config >"$CLASH_FILE")
    echo
    step "========================================"
    step "  安装完成！"
    step "========================================"
    echo
    render_client_info "$YELLOW" "$NC"
    echo
    step "Clash / mihomo 节点片段 (合并到客户端配置的 proxies 段):"
    render_clash_config
    echo
    step "以上信息已保存到 ${INFO_FILE}，Clash 片段已保存到 ${CLASH_FILE}"
    step "随时可执行 cat ${INFO_FILE} 或 cat ${CLASH_FILE} 查看"
    step "请妥善保存以上信息！"
}

validate_installed_config() {
    local output
    if ! output=$(docker run --rm -v "${CONFIG_DIR}:${CONFIG_DIR}" "$XRAY_IMAGE" xray run -test -c "$CONFIG_FILE" 2>&1); then
        printf '%s\n' "$output" | tail -n 5 >&2
        fail "现有配置 ${CONFIG_FILE} 未通过新镜像的 xray run -test 校验，容器 ${CONTAINER_NAME} 保持原样继续运行旧版本"
    fi
    info "现有配置已通过新镜像的 xray run -test 校验"
}

update_xray() {
    banner
    require_root
    require_curl
    if [ ! -f "$CONFIG_FILE" ]; then
        fail "未找到已安装的配置 ${CONFIG_FILE}，update 只更新已安装的 Xray，请先执行安装命令"
    fi
    ensure_docker
    if ! docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
        fail "未找到容器 ${CONTAINER_NAME}，update 只更新已安装的 Xray，请先执行安装命令"
    fi
    local flat old_id new_id old_version new_version
    flat=$(tr -d ' \t\r\n' <"$CONFIG_FILE")
    port=$(config_port "$flat")
    if ! valid_port "$port"; then
        fail "已有配置中的端口不合法 (值: ${port:-空})，无法校验启动状态，请重新执行安装命令"
    fi
    port=$((10#$port))
    info "update 只更新镜像与容器，配置、UUID、密钥、SNI、端口 ${port}、WARP 与 BBR 设置均保持不变"
    old_id=$(image_id)
    old_version=$(image_xray_version)
    step "正在拉取最新镜像 ${XRAY_IMAGE}..."
    docker pull "$XRAY_IMAGE" || fail "拉取镜像 ${XRAY_IMAGE} 失败，容器与配置保持不变"
    new_id=$(image_id)
    new_version=$(image_xray_version)
    if [ -n "$old_id" ] && [ "$old_id" = "$new_id" ]; then
        info "镜像已是最新 (Xray ${new_version:-版本未知}, imageId: ${new_id})，跳过重建容器"
        step "无需更新，客户端配置不受影响"
        return
    fi
    info "镜像已更新 (Xray ${old_version:-版本未知} -> ${new_version:-版本未知})"
    validate_installed_config
    step "正在用新镜像重建容器 ${CONTAINER_NAME}..."
    remove_old_container
    run_container
    wait_for_xray
    echo
    step "========================================"
    step "  更新完成！Xray ${old_version:-版本未知} -> ${new_version:-版本未知}"
    step "========================================"
    step "客户端配置未变动，无需重新导入；可执行 cat ${INFO_FILE} 查看"
}

install_xray() {
    banner
    require_root
    require_curl
    load_existing_config
    choose_sni
    choose_port
    choose_bbr
    choose_warp
    choose_fallback
    check_sni_tls13
    detect_server_ip
    check_sni_not_self
    ensure_docker
    ensure_image
    prepare_credentials
    setup_warp
    setup_fallback
    check_port_free
    write_and_test_config
    start_container
    wait_for_xray
    setup_warp_sync
    open_firewall
    enable_bbr
    show_result
}

main() {
    case "${1:-}" in
        "") install_xray ;;
        update) update_xray ;;
        *) fail "未知参数: $1，用法: bash onekey_xray.sh (安装/重装) 或 bash onekey_xray.sh update (只更新 Xray 镜像与容器)" ;;
    esac
}

main "$@"
