# Xray VLESS + Reality 一键安装

基于 Docker 一键部署 Xray（VLESS + Reality + xtls-rprx-vision），无需域名与证书；可选开启 BBR 加速与 Cloudflare WARP 分流。

## 一键安装

以 root 登录服务器后执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/afret0/v2ray/master/onekey_xray.sh)
```

按提示依次输入，直接回车即取默认值：

| 提示 | 默认值 |
| --- | --- |
| 伪装目标域名（SNI） | `www.microsoft.com` |
| 监听端口 | `443` |
| 是否开启 BBR 加速 | 开启 |
| 是否开启 Cloudflare WARP 分流 | 不开启 |

安装完成后会打印客户端配置和 `vless://` 分享链接，导入客户端即可使用。

### 免交互安装

通过环境变量传参，不再提示输入：

```bash
XRAY_SNI=www.microsoft.com XRAY_PORT=443 XRAY_BBR=y XRAY_WARP=n bash <(curl -fsSL https://raw.githubusercontent.com/afret0/v2ray/master/onekey_xray.sh)
```

| 环境变量 | 说明 | 默认值 |
| --- | --- | --- |
| `XRAY_SNI` | 伪装目标域名（dest / SNI），需是能从服务器访问、支持 TLS 1.3 的第三方网站 | `www.microsoft.com`，重装时为已安装的值 |
| `XRAY_PORT` | 监听端口，1-65535 | `443`，重装时为已安装的值 |
| `XRAY_BBR` | 是否开启 BBR，`y` / `n` | `y` |
| `XRAY_WARP` | 是否开启 WARP 分流，`y` / `n` | `n`，重装时为已安装的状态 |

## 脚本做了什么

1. 未安装 Docker 时通过 get.docker.com 自动安装；Rocky / AlmaLinux / Oracle Linux 等 get.docker.com 装不上时，改用 Docker 官方 centos 源安装；
2. 检测伪装站是否支持 TLS 1.3（不通过只提示）；伪装站解析到本机时直接报错退出，避免 REALITY 自己连自己耗尽资源；
3. 生成 UUID、x25519 密钥对与 ShortId，写入 `/etc/xray/config.json`，并用 `xray run -test` 校验；
4. 确认端口未被其他进程占用后，以 `xray-reality` 容器（`teddysun/xray` 镜像，host 网络）启动，并检查端口已在监听；容器日志按 10MB × 3 份轮转，不会无限增长；
5. ufw / firewalld 处于启用状态时自动放行该端口；
6. 按选择开启 BBR 与 WARP 分流（见下文）；
7. 打印客户端配置、分享链接与 BBR / WARP 状态，同时保存到 `/etc/xray/client-info.txt`。

## BBR 加速

- 设置 `net.ipv4.tcp_congestion_control = bbr` 与 `net.core.default_qdisc = fq`，写入 `/etc/sysctl.d/99-xray-bbr.conf`，重启后保持；重复执行只覆盖该文件，不会重复追加；
- 内核不支持 BBR，或 OpenVZ / LXC 等容器 VPS 无权修改内核参数时，提示后跳过，不升级内核；
- 选择不开启时不改动现有设置（之前已开启的 BBR 保持不变）。

## WARP 分流

- 使用 Xray 内置的 WireGuard 出站连接 Cloudflare WARP，不安装其他软件、不改动服务器自身的网络与路由；
- 以下站点经 WARP 出站，其余流量直连：`geosite:category-ai-!cn`（ChatGPT、Claude、Gemini 等非中国大陆 AI 服务）、`geosite:netflix`、`geosite:disney`；
- 经 WARP 出站时 IPv4 优先；
- 安装时自动注册免费 WARP 账号并检测连通性，注册失败或连不通时跳过 WARP，Reality 照常安装；
- 重装时沿用已安装的 WARP 状态并复用 WARP 账号，不会重复注册。

## 重装 / 修改配置

再次执行一键安装命令即可。脚本会复用 `/etc/xray/config.json` 里的 UUID、密钥与 ShortId，SNI、端口与 WARP 状态默认沿用已安装的值；只改了端口或 SNI 时，客户端改对应字段即可。修改端口后，旧端口的防火墙放行规则不会自动删除，脚本会打印删除命令。

如需重新生成 UUID 与密钥，先删除旧配置再执行安装命令：

```bash
rm -f /etc/xray/config.json
bash <(curl -fsSL https://raw.githubusercontent.com/afret0/v2ray/master/onekey_xray.sh)
```

## 常用命令

| 操作 | 命令 |
| --- | --- |
| 查看客户端配置与分享链接 | `cat /etc/xray/client-info.txt` |
| 查看日志 | `docker logs -f xray-reality` |
| 重启 | `docker restart xray-reality` |
| 关闭 WARP 分流 | `XRAY_WARP=n bash <(curl -fsSL https://raw.githubusercontent.com/afret0/v2ray/master/onekey_xray.sh)` |
| 关闭 BBR | `rm -f /etc/sysctl.d/99-xray-bbr.conf` 后重启服务器 |
| 卸载 | `docker rm -f -v xray-reality && rm -rf /etc/xray` |

## 说明

- 需要 root 权限与 curl；已在 Ubuntu 24.04、Debian 13 虚拟机上实测全新安装、重装、重启自启、BBR、WARP 分流，并在 Rocky Linux 9 上实测 centos 源兜底安装；
- 云服务器的安全组需自行放行所选 TCP 端口；
- 客户端需支持 VLESS + Reality，如 v2rayN、v2rayNG、Shadowrocket、Clash Meta（mihomo）。
