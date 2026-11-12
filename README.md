# Xray VLESS + Reality 一键安装

基于 Docker 一键部署 Xray（VLESS + Reality + xtls-rprx-vision），无需域名与证书。

## 一键安装

以 root 登录服务器后执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/afret0/v2ray/master/onekey_xray.sh)
```

按提示输入伪装目标域名（SNI，默认 `www.microsoft.com`）和监听端口（默认 `443`），直接回车即取默认值。安装完成后会打印客户端配置和 `vless://` 分享链接，导入客户端即可使用。

### 免交互安装

通过环境变量传参，不再提示输入：

```bash
XRAY_SNI=www.microsoft.com XRAY_PORT=443 bash <(curl -fsSL https://raw.githubusercontent.com/afret0/v2ray/master/onekey_xray.sh)
```

| 环境变量 | 说明 | 默认值 |
| --- | --- | --- |
| `XRAY_SNI` | 伪装目标域名（dest / SNI），需能从服务器访问且支持 TLS 1.3 | `www.microsoft.com`，重装时为已安装的值 |
| `XRAY_PORT` | 监听端口，1-65535 | `443`，重装时为已安装的值 |

## 脚本做了什么

1. 未安装 Docker 时通过 get.docker.com 自动安装；
2. 检测伪装站是否支持 TLS 1.3（不通过只提示，不中断安装）；
3. 生成 UUID、x25519 密钥对与 ShortId，写入 `/etc/xray/config.json`，并用 `xray run -test` 校验；
4. 确认端口未被其他进程占用后，以 `xray-reality` 容器（`teddysun/xray` 镜像，host 网络）启动，并检查端口已在监听；
5. ufw / firewalld 处于启用状态时自动放行该端口；
6. 打印客户端配置与分享链接，同时保存到 `/etc/xray/client-info.txt`。

## 重装 / 修改端口或 SNI

再次执行一键安装命令即可。脚本会复用 `/etc/xray/config.json` 里的 UUID、密钥与 ShortId，SNI 和端口默认沿用已安装的值；只改了端口或 SNI 时，客户端改对应字段即可。

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
| 卸载 | `docker rm -f xray-reality && rm -rf /etc/xray` |

## 说明

- 需要 root 权限与 curl，已在 Ubuntu 24.04、Debian 12 上实测；
- 云服务器的安全组需自行放行所选 TCP 端口；
- 客户端需支持 VLESS + Reality，如 v2rayN、v2rayNG、Shadowrocket、Clash Meta（mihomo）。
