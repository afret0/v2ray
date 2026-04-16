#!/usr/bin/env bash

# auto install xray with VLESS + Reality

# Required: docker, openssl

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  VLESS + Reality 一键安装脚本${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# ---- 输入参数 ----
read -p "伪装目标域名 (SNI, 默认 www.microsoft.com): " sni
sni=${sni:-www.microsoft.com}
echo -e "${YELLOW}伪装目标 (dest/SNI): ${sni}${NC}"

read -p "监听端口 (默认 443): " port
port=${port:-443}
echo -e "${YELLOW}监听端口: ${port}${NC}"

# ---- 获取服务器 IP ----
server_ip=$(curl -s4 ifconfig.me || curl -s4 ip.sb || curl -s4 ipinfo.io/ip)
if [ -z "$server_ip" ]; then
    server_ip=$(curl -s6 ifconfig.me || curl -s6 ip.sb)
fi
echo -e "${YELLOW}服务器 IP: ${server_ip}${NC}"

# ---- 安装 Docker ----
if ! command -v docker &> /dev/null; then
    echo -e "${GREEN}正在安装 Docker...${NC}"
    curl -fsSL https://get.docker.com/ -o get-docker.sh
    sh get-docker.sh
    systemctl start docker
    systemctl enable docker
    rm -f get-docker.sh
else
    echo -e "${YELLOW}Docker 已安装，跳过${NC}"
fi

# ---- 下载配置文件 ----
mkdir -p /etc/xray
wget -O /etc/xray/config.json https://raw.githubusercontent.com/afret0/v2ray/reality/config.json

# ---- 生成密钥对 ----
# 先用临时容器生成 x25519 密钥对
echo -e "${GREEN}正在生成 Reality 密钥对...${NC}"
key_pair=$(docker run --rm teddysun/xray xray x25519)
private_key=$(echo "$key_pair" | grep "Private key:" | awk '{print $3}')
public_key=$(echo "$key_pair" | grep "Public key:" | awk '{print $3}')

echo -e "${YELLOW}Private Key: ${private_key}${NC}"
echo -e "${YELLOW}Public Key:  ${public_key}${NC}"

# ---- 生成 UUID ----
uuid=$(docker run --rm teddysun/xray xray uuid)
echo -e "${YELLOW}UUID: ${uuid}${NC}"

# ---- 生成 ShortId ----
short_id=$(openssl rand -hex 8)
echo -e "${YELLOW}Short ID: ${short_id}${NC}"

# ---- 替换配置文件中的占位符 ----
sed -i "s/REALITY_UUID/${uuid}/g" /etc/xray/config.json
sed -i "s/REALITY_PRIVATE_KEY/${private_key}/g" /etc/xray/config.json
sed -i "s/REALITY_DEST/${sni}/g" /etc/xray/config.json
sed -i "s/REALITY_SNI/${sni}/g" /etc/xray/config.json
sed -i "s/REALITY_SHORT_ID/${short_id}/g" /etc/xray/config.json

# 如果端口不是 443，替换端口
if [ "$port" != "443" ]; then
    sed -i "s/\"port\": 443/\"port\": ${port}/g" /etc/xray/config.json
fi

# ---- 停止并删除旧容器 (如果存在) ----
docker rm -f xray-reality 2>/dev/null || true

# ---- 启动 Xray 容器 ----
echo -e "${GREEN}正在启动 Xray Reality...${NC}"
docker run -d \
    --name xray-reality \
    --restart always \
    --net host \
    -v /etc/xray:/etc/xray \
    teddysun/xray

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  安装完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${GREEN}============ 客户端配置信息 ============${NC}"
echo -e "协议:       ${YELLOW}VLESS${NC}"
echo -e "地址:       ${YELLOW}${server_ip}${NC}"
echo -e "端口:       ${YELLOW}${port}${NC}"
echo -e "UUID:       ${YELLOW}${uuid}${NC}"
echo -e "流控:       ${YELLOW}xtls-rprx-vision${NC}"
echo -e "传输协议:   ${YELLOW}tcp${NC}"
echo -e "传输层安全:  ${YELLOW}reality${NC}"
echo -e "SNI:        ${YELLOW}${sni}${NC}"
echo -e "Fingerprint: ${YELLOW}chrome${NC}"
echo -e "PublicKey:   ${YELLOW}${public_key}${NC}"
echo -e "ShortId:     ${YELLOW}${short_id}${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# ---- 生成分享链接 ----
vless_link="vless://${uuid}@${server_ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp#Reality-${server_ip}"
echo -e "${GREEN}分享链接:${NC}"
echo -e "${YELLOW}${vless_link}${NC}"
echo ""
echo -e "${GREEN}请妥善保存以上信息！${NC}"