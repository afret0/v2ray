# Xray VLESS + Reality 一键安装

基于 Docker 一键部署 Xray（VLESS + Reality + xtls-rprx-vision），无需域名与证书；伪装站从候选池随机挑选并实测 TLS 1.3；可选开启 BBR 加速、Cloudflare WARP 分流与 REALITY 回落限速；输出 `vless://` 分享链接与 Clash / mihomo 节点片段，并支持一条命令更新内核。需要多用户管理（加人/删人、流量统计、到期时间、订阅链接）时，用 [onekey_3xui.sh](./onekey_3xui.sh) 安装 3x-ui 面板并无损接管节点，见下文「多用户管理」。

## 一键安装

以 root 登录服务器后执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/afret0/v2ray/master/onekey_xray.sh)
```

按提示依次输入，直接回车即取默认值：

| 提示 | 默认值 |
| --- | --- |
| 伪装目标域名（SNI） | 从候选池随机挑一个实测支持 TLS 1.3 的（见下文） |
| 监听端口 | `443` |
| 是否开启 BBR 加速 | 开启 |
| 是否开启 Cloudflare WARP 分流 | 不开启 |
| WARP 订阅列表 URL（开启 WARP 后追问） | 本仓库 [warp-domains.txt](./warp-domains.txt) 的 raw 地址，重装时沿用已装值，留空 = 不启用订阅 |
| 是否开启 REALITY 回落限速 | 不开启 |

安装完成后会打印客户端配置、`vless://` 分享链接与 Clash / mihomo 节点片段，导入客户端即可使用。

### 免交互安装

通过环境变量传参，不再提示输入：

```bash
XRAY_SNI=www.samsung.com XRAY_PORT=443 XRAY_BBR=y XRAY_WARP=n XRAY_FALLBACK_LIMIT=n bash <(curl -fsSL https://raw.githubusercontent.com/afret0/v2ray/master/onekey_xray.sh)
```

| 环境变量 | 说明 | 默认值 |
| --- | --- | --- |
| `XRAY_SNI` | 伪装目标域名（dest / SNI），需是能从服务器访问、支持 TLS 1.3 的第三方网站 | 从候选池随机挑选，重装时为已安装的值 |
| `XRAY_PORT` | 监听端口，1-65535 | `443`，重装时为已安装的值 |
| `XRAY_BBR` | 是否开启 BBR，`y` / `n` | `y` |
| `XRAY_WARP` | 是否开启 WARP 分流，`y` / `n` | `n`，重装时为已安装的状态 |
| `XRAY_WARP_LIST` | WARP 订阅列表 URL（https），每天自动拉取追加进 WARP 分流 | 本仓库 `warp-domains.txt` 的 raw 地址，重装时为已安装的值 |
| `XRAY_FALLBACK_LIMIT` | 是否开启 REALITY 回落限速，`y` / `n` | `n`，重装时为已安装的状态 |

## 脚本做了什么

1. 未安装 Docker 时通过 get.docker.com 自动安装；Rocky / AlmaLinux / Oracle Linux 等 get.docker.com 装不上时，改用 Docker 官方 centos 源安装；
2. 全新安装时从候选池随机挑选伪装站（见下文）；检测伪装站是否支持 TLS 1.3（不通过只提示）；伪装站解析到本机时直接报错退出，避免 REALITY 自己连自己耗尽资源；
3. 生成 UUID、x25519 密钥对与 ShortId，写入 `/etc/xray/config.json`，并用 `xray run -test` 校验；
4. 确认端口未被其他进程占用后，以 `xray-reality` 容器（`teddysun/xray` 镜像，host 网络）启动，并检查端口已在监听；容器日志按 10MB × 3 份轮转，不会无限增长；
5. ufw / firewalld 处于启用状态时自动放行该端口；
6. 按选择开启 BBR、WARP 分流与回落限速（见下文）；
7. 打印客户端配置、分享链接、Clash / mihomo 节点片段与 BBR / WARP / 回落限速状态，同时保存到 `/etc/xray/client-info.txt` 与 `/etc/xray/clash.yaml`。

## 伪装目标（SNI）怎么选

REALITY 借用伪装站的证书与握手特征，伪装站选得不对会提高服务器 IP 被封的概率。Xray 自身会对这几类目标打警告（源码 `infra/conf/transport_security.go`）：域名后缀 `.cn` / `.ru` / `.ir`，或域名里含 `apple` / `icloud` / `microsoft`——它们是被 REALITY 用烂的目标，且这类流量不该大量出现在一台境外小 VPS 上。监听端口不是 443 也会警告。

脚本内置候选池，**全新安装时打乱顺序逐个用 `curl --tlsv1.3` 探测（每个超时 10 秒），取第一个通过的**作为默认值；全部不通过时仍取池内一个并打印警告，可用 `XRAY_SNI` 指定：

```text
www.samsung.com  www.amd.com  www.tesla.com  www.cisco.com  www.autodesk.com
```

重装时沿用已安装的 SNI，不重新挑池。

**官方最佳实践是「偷同 ASN 的证书」**：伪装站与你的 VPS 在同一机房/同一 ASN，抗主动探测效果最好，这种情况下也根本不需要回落限速。候选池只是通用起点，所有用本脚本的人池子相同，本身也有批量特征，讲究的话请自己挑同 ASN 的站点：

```bash
curl -s ipinfo.io/org                                   # 查本机 ASN
docker run --rm teddysun/xray xray tls ping www.samsung.com   # 验证候选
```

`tls ping` 要看四项：`Handshake succeeded`、`TLS Version: TLS 1.3`、`TLS Post-Quantum key exchange: true (X25519MLKEM768)`、证书链长度够大。批量扫描同 ASN 网段可用官方工具 [XTLS/RealiTLScanner](https://github.com/XTLS/RealiTLScanner)。选站还要避开 Cloudflare 这类共享免费 CDN（否则服务器变成别人的免费中转）和国内被墙的域名。

换 SNI 不用换凭据：`XRAY_SNI=<新域名> bash <(curl …)`，客户端只改 SNI 一个字段。

## 更新 Xray 内核

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/afret0/v2ray/master/onekey_xray.sh) update
```

- 强制拉取最新 `teddysun/xray` 镜像（同时更新镜像内的 geosite / geoip 数据），有新版本时先用新镜像 `xray run -test` 校验现有配置，再重建容器并检查端口监听；
- 配置、UUID、密钥、SNI、端口、WARP 账号与 BBR 设置全部保持不变，**客户端无需重新导入**；不重跑 WARP 注册、防火墙放行与 BBR 设置；
- 镜像已是最新时只提示，不重建容器；新镜像校验现有配置失败时直接退出，旧容器继续运行；
- 未安装（没有 `/etc/xray/config.json` 或没有 `xray-reality` 容器）时 `update` 直接报错，请先执行安装命令；
- 旧版本脚本装好的机器若要拿到 `clash.yaml`、新的候选池 SNI 或回落限速开关，重跑一次安装命令即可（凭据复用，客户端不用换）。

## REALITY 回落限速（默认不开启）

REALITY 会把认证失败的连接原样转发到伪装站，服务器因此可能被扫描者当成免费端口转发偷跑流量。开启后脚本给回落连接的上下行各写一组限速参数：

| 参数 | 中心值 | 含义 |
| --- | --- | --- |
| `afterBytes` | `10485760` | 单条回落连接传输约 10MB 后开始限速 |
| `bytesPerSec` | `1048576` | 基准速率约 1MB/s |
| `burstBytesPerSec` | `5242880` | 令牌桶容量约 5MB，允许突发 |

- **默认不开启**：Xray 官方文档明确「回落限速是一种特征，不建议启用」，伪装站与本机同 ASN 时用不到；只有偷了 Cloudflare 这类共享 CDN 的证书、担心被当免费中转时才建议开；
- 开启方式：交互选 `y`，或 `XRAY_FALLBACK_LIMIT=y bash <(curl …)`；
- **六个参数各自在中心值 ±30% 内随机取值**（官方要求一键脚本必须随机化，否则所有装机回落行为一致，反而成批量指纹），实际取值会打印出来并记入 `client-info.txt`；
- 重装时沿用已安装的开关状态并**复用已装的参数值**，不重新随机；关闭时把这两个字段从配置中移除；
- **已通过认证的客户端连接完全不受限速影响**。

## Clash / mihomo 导出

安装结束会打印并保存 `/etc/xray/clash.yaml`，内容是标准 mihomo `proxies` 节点片段（`type: vless` + `reality-opts` + `flow: xtls-rprx-vision`），把它合并进客户端配置的 `proxies` 段、再在 `proxy-groups` 里引用节点名 `Reality-<服务器IP>` 即可：

```yaml
proxies:
  - name: "Reality-203.0.113.10"
    type: vless
    server: "203.0.113.10"
    port: 443
    uuid: "<UUID>"
    flow: xtls-rprx-vision
    network: tcp
    tls: true
    udp: true
    client-fingerprint: chrome
    servername: www.samsung.com
    reality-opts:
      public-key: "<PublicKey>"
      short-id: "<ShortId>"
```

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

### WARP 订阅列表（改列表不登服务器）

内置三条 geosite 之外，可以再挂一个**远程域名订阅**：你在 GitHub 网页 / 手机上编辑列表文件，服务器每天自动拉取，内容变化时校验通过后自动应用，不用登录服务器。

- 列表默认用本仓库的 [warp-domains.txt](./warp-domains.txt)（fork 后改自己仓库的文件，并用 `XRAY_WARP_LIST` 指向自己的 raw 地址）；安装时输入其它 https URL 也行，留空 = 不启用订阅；
- **格式**：每行一条规则，`#` 开头整行为注释、空行忽略、不支持行尾注释。裸域名 = 该域名及其全部子域名走 WARP；也支持 Xray 原生前缀 `full:`（精确匹配）、`keyword:`、`regexp:`、`geosite:`；非法行**跳过并记日志**，其余行照常生效；重复行去重；上限 1000 条；
- **机制**：同步器 `/etc/xray/warp-sync.sh` 由 systemd timer（`xray-warp-sync.timer`，每天一次，随机延迟半小时内；无 systemd 时落 cron）驱动：拉取 → 解析 → 内容与上次相同则什么都不做；变化时把「内置 + 订阅」重写进 `routing`，先 `xray run -test` 校验，通过才重建容器（秒级断线）；校验失败或拉取失败都**保持现有配置**，下轮重试；新容器起不来时按旧配置自动回滚；
- 装完当场就拉取一次并入首份配置（拉取失败只提示，节点照常装）；重装沿用已装 URL（`XRAY_WARP_LIST` 可覆盖）；**关闭 WARP 时同步器一并移除**；
- 手动立即同步：`bash /etc/xray/warp-sync.sh`；看同步日志：`journalctl -u xray-warp-sync.service`；
- `update` 子命令不动订阅与同步器；3x-ui 面板接管时会把**上次成功同步的订阅快照**一并写进面板模板并移除同步器，之后在面板里管理分流。

## 重装 / 修改配置

再次执行一键安装命令即可。脚本会复用 `/etc/xray/config.json` 里的 UUID、密钥与 ShortId，SNI、端口与 WARP 状态默认沿用已安装的值；只改了端口或 SNI 时，客户端改对应字段即可。修改端口后，旧端口的防火墙放行规则不会自动删除，脚本会打印删除命令。

如需重新生成 UUID 与密钥，先删除旧配置再执行安装命令：

```bash
rm -f /etc/xray/config.json
bash <(curl -fsSL https://raw.githubusercontent.com/afret0/v2ray/master/onekey_xray.sh)
```

## 多用户管理（3x-ui 面板）

单 UUID 脚本适合自用；要给多人分发、按人看流量、设到期、随时吊销某个人，用面板脚本 [onekey_3xui.sh](./onekey_3xui.sh)：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/afret0/v2ray/master/onekey_3xui.sh)
```

脚本做的事：

1. **没装过节点**：先调用本仓库的 `onekey_xray.sh` 安装 Reality 节点（同目录有该文件就用本地的，没有就从本仓库下载；SNI / 端口 / BBR / WARP / 回落限速的交互提问原样透传，也可先用 `XRAY_*` 环境变量装好节点再跑面板脚本）；
2. **已装过节点**：读取 `/etc/xray/config.json`，把端口、SNI、UUID、私钥、ShortId **原样**建成面板入站，**旧客户端一个都不用重新导入**；回落限速的六个随机值原样带入（3x-ui 的 Reality 表单支持 `limitFallbackUpload/Download`）；WARP 账号与分流规则（内置三条 + 订阅列表快照）写入面板的 Xray 模板（出站 tag 为 `warp`，之后可在面板 WARP 页换 IP / 填 license），接管成功后移除 WARP 订阅定时同步器；
3. Docker 部署官方 `ghcr.io/mhsanaei/3x-ui` 镜像（host 网络，容器名 `3x-ui`，数据库持久化在 `/etc/x-ui`，日志 10MB × 3 份轮转）；面板端口在 20000-60000 随机选取（可用 `XUI_PORT` 指定），用户名 / 密码 / 访问路径全部随机生成；
4. 通过面板 API 建好入站并校验通过后，才移除旧的 `xray-reality` 容器让出端口；面板 Xray 未在 15 秒内监听端口时**自动回滚**：禁用面板入站并按原配置恢复旧容器；`/etc/xray` 下的旧配置与客户端信息始终保留，可随时手动回退；
5. 打印并保存面板地址 / 账号 / 密码到 `/etc/x-ui/panel-info.txt`（仅 root 可读），ufw / firewalld 启用时自动放行面板端口。

装完后在面板「入站列表 → Reality-<IP> → 添加客户端」即可加人，每个用户独立 UUID，面板自带流量统计、到期时间、IP 限制与订阅链接；迁移过来的原用户名为 `user1`，可在面板里改名。

注意：

- **重复执行是安全的**：面板容器已存在时只展示现有面板信息后退出，不重置账密、不动已有用户；
- 面板是 HTTP 明文，靠随机端口 + 随机路径 + 随机账密保护，**不要外传面板地址**；需要 HTTPS 时在面板设置里配证书；
- 节点接管后，`onekey_xray.sh` 的安装 / `update` 命令**不要再对这台机器执行**（会跟面板抢端口），内核与面板更新都在面板里操作；
- 卸载面板：`docker rm -f -v 3x-ui && rm -rf /etc/x-ui`；想退回单节点脚本，恢复旧容器即可：`docker run -d --name xray-reality --restart always --net host -v /etc/xray:/etc/xray teddysun/xray`。

## 常用命令

| 操作 | 命令 |
| --- | --- |
| 查看客户端配置与分享链接 | `cat /etc/xray/client-info.txt` |
| 查看 Clash / mihomo 节点片段 | `cat /etc/xray/clash.yaml` |
| 更新 Xray 内核 | `bash <(curl -fsSL https://raw.githubusercontent.com/afret0/v2ray/master/onekey_xray.sh) update` |
| 查看日志 | `docker logs -f xray-reality` |
| 重启 | `docker restart xray-reality` |
| 开启回落限速 | `XRAY_FALLBACK_LIMIT=y bash <(curl -fsSL https://raw.githubusercontent.com/afret0/v2ray/master/onekey_xray.sh)` |
| 关闭 WARP 分流 | `XRAY_WARP=n bash <(curl -fsSL https://raw.githubusercontent.com/afret0/v2ray/master/onekey_xray.sh)` |
| 立即同步 WARP 订阅列表 | `bash /etc/xray/warp-sync.sh` |
| 查看 WARP 订阅同步日志 | `journalctl -u xray-warp-sync.service` |
| 更换 WARP 订阅列表 URL | `XRAY_WARP_LIST=<https-url> bash <(curl -fsSL https://raw.githubusercontent.com/afret0/v2ray/master/onekey_xray.sh)` |
| 关闭 BBR | `rm -f /etc/sysctl.d/99-xray-bbr.conf` 后重启服务器 |
| 安装 3x-ui 面板（多用户管理） | `bash <(curl -fsSL https://raw.githubusercontent.com/afret0/v2ray/master/onekey_3xui.sh)` |
| 查看面板地址与账密 | `cat /etc/x-ui/panel-info.txt` |
| 卸载 | `docker rm -f -v xray-reality && rm -rf /etc/xray` |

## 说明

- 需要 root 权限与 curl；已在 Ubuntu 24.04、Debian 13 虚拟机上实测全新安装、重装、重启自启、BBR、WARP 分流，并在 Rocky Linux 9 上实测 centos 源兜底安装；
- 云服务器的安全组需自行放行所选 TCP 端口；
- 客户端需支持 VLESS + Reality，如 v2rayN、v2rayNG、Shadowrocket、Clash Meta（mihomo）；
- 回落限速需要 Xray-core 支持 `limitFallbackUpload` / `limitFallbackDownload`（旧内核会忽略这两个字段，执行 `update` 升级即可生效）；
- 候选池 5 个域名已实测支持 TLS 1.3 与 X25519MLKEM768，但网络环境随时会变，脚本每次装机都会在服务器上重新探测；
- `onekey_3xui.sh` 的面板 API 全链路（随机账密写入、API Token、同参数入站创建、WARP 模板校验、启用接管、分享链接含 pbk/fp）已对真实 3x-ui 3.11.0 容器实测通过，凭据与回落限速值逐项断言原样保留；整机安装流程（root、防火墙、旧容器切换）尚未在 Linux 虚拟机上端到端实测。
