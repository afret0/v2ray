# v2ray 仓库说明

单文件 Bash 一键脚本仓库：[onekey_xray.sh](../onekey_xray.sh) 在 Linux 服务器上用 Docker 部署 Xray（VLESS + Reality + Vision），可选 BBR 与 Cloudflare WARP 分流。没有构建系统、没有依赖清单，改完只需下面的验证命令。

## 入口与子命令

`main "$@"` 用 `case` 分派：无参数 = `install_xray`（安装/重装），`update` = `update_xray`（只换镜像与容器），其它参数一律 `fail` 并打印用法。新增子命令必须同时改这个 `case` 和 README 的命令表。

`update` 的既定语义（用户确认过，改动前先问）：只 `docker pull` + 校验现有配置 + 重建容器；**不重跑** WARP 注册、防火墙放行、BBR、凭据生成；镜像 Id 未变则跳过重建；新镜像校验现有配置失败则退出且保留旧容器；缺配置或缺容器直接报错而不是顺手安装。

## 脚本约定

- 顶部 `readonly` 常量集中放路径、镜像名、阈值；新增可调值也放这里，不散写字面量。
- 输出只用三个 helper：`step`（绿，阶段）、`info`（黄，判定与结果）、`fail`（红，报错并 `exit 1`）。文案中文，每个提前退出都要说清被哪条规则拦下、实际值是多少。
- 不写注释；靠 `valid_*` 校验函数、`render_*` heredoc、`check_*` / `ensure_*` 动作函数命名表达意图。
- 配置生成走 `render_config` → `write_and_test_config`（`xray run -test` 校验临时文件）→ `start_container`（`mv` 覆盖 + `remove_old_container` + `run_container`）。**任何新配置字段都必须先过 `xray run -test` 再落地**，容器启动参数只在 `run_container` 一处维护。
- 重装复用凭据：`load_existing_config` 从旧 `config.json` 正则提取 UUID / 私钥 / ShortId / SNI / 端口 / WARP 账号，改解析逻辑时同步 `config_port` 等 helper，避免两处正则漂移。

## 伪装站与回落限速的既定设计（用户确认过）

- 全新安装的 SNI 从 `SNI_POOL` 打乱后逐个 `curl --tlsv1.3` 探测取首个通过的；重装沿用已装 SNI，不重新挑池。改池内容要先问用户。
- Xray 会对 `.cn`/`.ru`/`.ir` 后缀与含 `apple`/`icloud`/`microsoft` 的 `serverNames` 打 GFW 警告（`infra/conf/transport_security.go`），非 443 监听端口也警告（`infra/conf/xray.go`）。池里不要放这类域名。
- 官方最佳实践是「偷同 ASN 的证书」，其次要求 TLS1.3 + X25519（最好 X25519MLKEM768）、非共享免费 CDN、国内未被墙。验证命令：`docker run --rm teddysun/xray xray tls ping <域名>`，看 `Handshake succeeded` / `TLS 1.3` / `Post-Quantum ... true` / 证书链长度。批量扫同 ASN 用 XTLS/RealiTLScanner。
- **回落限速默认关闭**，`XRAY_FALLBACK_LIMIT=y` 才开：官方文档明确「回落限速是一种特征，不建议启用，面板/一键脚本开发者务必让参数随机化」。所以六个值各自在中心值 ±`FALLBACK_JITTER_PERCENT`% 内随机（`jitter_value`），**禁止改回写死常量**——那会让所有装机行为一致，成为批量指纹。重装复用已装值（`load_existing_fallback` + `reuse_fallback`），与 WARP 账号复用同一套模式。

## 已验证的坑

- `ensure_image` 见到本地已有镜像就跳过 `docker pull`，所以**重装不会更新内核与 geosite/geoip**；更新只能走 `update` 子命令，别把 pull 塞回安装路径。
- `key_from_output` 必须同时认 `Public key` 与新版 `Password` 标签：Xray 26 改了 `xray x25519` 的输出字段名。
- Xray 的 JSON 配置加载器**忽略未知字段**（实测：往 `realitySettings` 塞不存在的字段仍 `Configuration OK`），所以新字段对旧内核安全，但也意味着拼错字段名不会报错，只能靠断言校验。
- Clash / mihomo 片段里 `short-id` 必须带引号：纯数字的 hex shortId 不加引号会被 YAML 解析成整数；IPv6 的 `server` 同样加引号，而 `vless://` 链接里的 IPv6 要加 `[]`。
- 从 macOS 本机探测 target 的结果不可信：本机走代理，域名会解析到 `198.18.x` fake-ip，`tls ping` 的成败与真实服务器不同（实测 `www.nvidia.com` 本机握手失败）。候选池必须在目标服务器上复测。
- 在 harness 里 `source` 脚本副本会连带继承 `set -Eeuo pipefail` 与 ERR trap，测试脚本里断言「某命令应当失败」前必须 `set +e +E; trap - ERR`，否则第一条负面断言就会中断整个测试。
- 随机化相关的断言不能写死次数/顺序：候选池打乱后「探测了几个」「有没有降级日志」都随顺序变化，断言要写成区间或条件式，否则测试会随机红。
- 客户端信息文件含 UUID / 私钥推导出的公钥，落盘一律 `(umask 077 && render_xxx >file)`。

## 验证命令（macOS 本机可跑，已实测）

```bash
bash -n onekey_xray.sh
docker run --rm -v "$PWD:/mnt:ro" koalaman/shellcheck:stable -S style /mnt/onekey_xray.sh
```

基线：shellcheck 全 severity 零告警，改完必须保持零告警（本机没装 shellcheck，用上面的 docker 方式跑）。

真实内核与客户端校验（Docker Desktop 可用时）：把脚本去掉末行 `main "$@"` 后 `source` 进临时 harness，设好 `sni/port/uuid/private_key/public_key/short_id/server_ip/warp_*`，调用 `render_config` / `render_clash_config`，然后

```bash
docker run --rm -v /tmp/harness:/tmp/harness teddysun/xray xray run -test -c /tmp/harness/cfg.json
docker run --rm -v /tmp/harness/clash:/root/.config/mihomo metacubex/mihomo:latest -t -d /root/.config/mihomo -f /root/.config/mihomo/config.yaml
```

mihomo 需要完整配置才肯校验：在片段前后补 `mixed-port/mode/log-level` 与 `proxy-groups/rules`。WARP 与回落限速的开关组合（都关 / 只开限速 / 都开）三种 `render_config` 输出都要过 xray 校验；限速开启时用 python 断言六个值都落在中心 ±30% 区间内。

流程分支（`update`、`pick_default_sni`、`choose_*` 这类）在 macOS 上跑不了真实安装（需要 root、`ss`、`getent`、Linux 内核参数）：用 PATH 前置的假 `docker` / `curl` stub + 把 `CONFIG_DIR` sed 成临时目录的脚本副本，覆盖「缺配置 / 缺容器 / 已最新 / 有新版 / 校验失败 / 端口非法」与「候选逐个降级 / 全失败兜底 / 首个通过即停 / XRAY_SNI 覆盖 / 重装沿用」分支，并断言 `docker` 调用序列里该不该出现 `rm -f -v`。真实端到端只在 Ubuntu / Debian / Rocky 虚拟机上做，做完把结论写进 README 的说明段。

## 提交

commit message 沿用仓库惯例：小写英文 `<type> <描述>`，如 `feat add bbr and warp options, stop log and volume accumulation`、`doc bbr warp options and log rotation`。改脚本行为必须同步 README（功能说明 + 常用命令表）。