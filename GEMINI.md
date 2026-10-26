# GEMINI.md - 项目记忆与规则沉淀

本文件由 Antigravity 自动加载，用于在各次对话中沉淀开发者的本地环境配置与重要经验规则。

---

## 1. 本机开发与调试环境

### ADB 绝对路径（重要）
当需要执行 `adb` 命令（如查看设备、安装测试 APK、拉取 `run.log`、查看 `logcat` 等）时，**必须使用该绝对路径调用**：

```cmd
"D:\UNLOCKER\莫离然然搞机工具箱v4.7.5-2026.3.17\Tools\adb.exe"
```

示例命令：
- 检查连接设备：`& "D:\UNLOCKER\莫离然然搞机工具箱v4.7.5-2026.3.17\Tools\adb.exe" devices -l`
- 查看实时日志：`& "D:\UNLOCKER\莫离然然搞机工具箱v4.7.5-2026.3.17\Tools\adb.exe" logcat -s Esurfing`
- 拉取后台日志：`& "D:\UNLOCKER\莫离然然搞机工具箱v4.7.5-2026.3.17\Tools\adb.exe" shell "cat /data/adb/esurfing/run.log"`

同目录下包含 `fastboot.exe`：
```cmd
"D:\UNLOCKER\莫离然然搞机工具箱v4.7.5-2026.3.17\Tools\fastboot.exe"
```

### PowerShell 7 (pwsh) 与统一 UTF-8 规范（铁律）
- **全面锁定使用 PowerShell 7 (`pwsh`)**：
  - 本机已安装并默认启用 **PowerShell 7 (`pwsh.exe`)**（路径为 `C:\Users\LFQ\AppData\Local\Microsoft\WindowsApps\Microsoft.PowerShell_8wekyb3d8bbwe\pwsh.exe`，命令行直接调用 `pwsh`）。
  - 后续所有终端命令、自动化脚本、构建任务与交互**必须统一使用 `pwsh`**，全面弃用系统自带的旧 Windows PowerShell 5.1（`powershell.exe`）。
- **统一 UTF-8 编码规范**：
  - 虽然 PowerShell 7 的重定向（`>`）与管道默认编码已为标准无 BOM 的 `utf8NoBOM`，但在向 Android / Linux / 远程服务器生成、写入或传输任何配置文件、HTML、Shell 脚本时，**必须显式声明 UTF-8 编码**（如 `Set-Content -Encoding utf8`、`Out-File -Encoding utf8`、Python 二进制模式写入或 `[System.IO.File]::WriteAllBytes`）。
  - 严禁产生任何带 BOM 或 UTF-16 的非标准格式，杜绝中文乱码、语法解析崩溃与 `/bin/sh: ...^M: not found` 换行符异常。

### 接口调试与 Mongoose 避坑
- **严禁使用 `curl -I` 探测守护进程 Web 接口**：`WebServer.c` 的轻量路由仅匹配了 `GET` 和 `POST`。发送 `HEAD` 动词（`curl -I`）会导致连接无任何响应并挂起死锁。应使用 `curl -s -i` 并配合超时参数。

---

## 2. WebUI 与 KernelSU 通信规则
- **KernelSU WebUI 端口隔离**：KernelSU WebUI 运行于内核管理器自建的随机端口 HTTP 服务中。`webroot/index.html` 中的 API 请求地址**必须显式指向 `http://127.0.0.1:8888`**，绝不能使用相对路径或基于 `location.origin.startsWith('http')` 进行清空，否则会导致所有请求发向 KernelSU 自身引发 404 断连。
- 后端 `WebServer.c` 必须始终保持注入 `cors_hdrs`（包含 `Access-Control-Allow-Origin: *`）。

---

## 3. 网络代理冲突与 Box4Magisk 经验

### 连通性探测地址
客户端底层（`NetClient.c`）探测网络通畅与 Portal 拦截状态依赖以下目标：
1. **主检测**：`http://connect.rom.miui.com/generate_204`（期望 204 为正常联网，302 为需认证）
2. **备用检测**：`http://1.1.1.1`（期望 301 为正常联网，302 为需认证）
3. **认证服务器**：`http://14.146.227.141:7001`、`http://121.8.177.212:7001`
4. **心跳保活**：校园网内部网关 AC（通常为私有网段或校内 IP）

### Box4Magisk / sing-box 共存规则
若同时启用 Box4Magisk（基于 iptables 的 sing-box 透明代理）：
- **Flutter APK 版**：在 WebUI 或 `exclude.list` 中排除包名 `com.example.esurfing_client`。
- **Magisk Daemon 版（`esurfing-daemon` / `esurfingd`）**：
  1. **禁止在 `ap_list` 中包含客户端网卡**：`/data/adb/singbox/settings.ini` 中的 `ap_list` 绝对不能包含 `"wlan+"` 或 `"rmnet+"`！否则会将 Wi-Fi 和蜂窝网的所有入站响应包（如认证服务器的 TCP SYN-ACK）误当成热点流量进行 TPROXY 劫持，导致 curl 报错误码 28（操作超时）。
  2. **内网与校园网段放行**：
     - 在 `/data/adb/singbox/scripts/constants.sh` 的 `INTRANET_V4` 中加入：`100.0.0.0/8`（覆盖高校 Wi-Fi 常见的 `100.2.x.x` 内部网段）、`1.1.1.1/32`、`220.181.104.183/32`（`connect.rom.miui.com` 固定探测 IP，防止被 `tproxy-in` 的 `sniff_override_destination: true` 还原为域名并在息屏/未认证断流时触发 DoH `223.5.5.5:443` 死锁）、`125.88.59.131/32`、`14.146.227.141/32`、`121.8.177.212/32`。
     - 守护进程 `esurfingd` 在 `__MAGISK__` 模式下启动时会自动调用 `setgid(3005)`（`AID_NET_ADMIN`）并写入 `/sys/power/wake_lock`，自动命中 `iptables` `BOX_LOCAL` 的首条直连规则（`UID 0 + GID 3005 -> RETURN`）并防止息屏 Doze 冻结心跳定时器。
     - 在 `iptables.sh` 中，`bypass_intranet` 规则必须置于 `handle_packages`（应用过滤）之前，且**仅能使用 `-d "${subnet}"`（目的地址匹配），绝对不能加 `-s "${subnet}"`**！因为手机连接 Wi-Fi 获得的本地 IP（如 `100.2.x.x`、`192.168.x.x`）本身就属于内网网段，如果对 `-s` 做 RETURN，将导致本机发送的所有公网数据包全部被误当成内网直连放行，使透明代理彻底失效导致无法上外网/谷歌。
  3. 在 `config.json` 的 `route.rules` 与 `dns.rules` 中：
     - `route.rules`：将校园网直连域名（`rom.miui.com`、`edu.cn`、`cndatacom.com`、`cdcc.cn`、`189.cn`、`gd189.cn`）以及认证网关 IP（`1.1.1.1`、`14.146.227.141`、`121.8.177.212`）设为 `DIRECT`。
     - `dns.rules`：校园网及国内直连域名务必使用 `dns_direct`（即 DoH `https://223.5.5.5`），**切勿将直连域名指向 `local` DNS**！原因：在 Android TPROXY 模式下，`local` DNS 解析会调用 Bionic libc 的 `getaddrinfo`，该调用通过 Unix Domain Socket 委托给 Android 系统服务 `netd`（`android.uid.system`，UID 1000）。`netd` 发出的 UDP 53 端口数据包由于不具备 sing-box 的 UID/GID 标记，会被 iptables 重新劫持回 sing-box 的 TPROXY 端口进而被 `hijack-dns` 捕获，引发严重的死循环导致域名解析完全超时失败；此外 sing-box 1.12+ 若为 `local` DNS 声明 `"detour": "DIRECT"` 会报错 `detour to an empty direct outbound makes no sense`。
  4. **应用级防断流名单**：在 `/data/adb/singbox/exclude.list` 中务必同时加入：
     - `com.cndatacom.campus.cdccportalgd`（校园网官方 CDCC 客户端）
     - `com.example.esurfing_client`（本开源客户端）

### 5. sing-box 规则与 Google Play / 微信避坑经验
- **`client_subnet` 全局污染陷阱**：严禁在 `dns` 根层级配置全局 `client_subnet`（如 `223.5.5.0/24`）。否则发送给 Google DNS（`8.8.8.8`）时 Google 会按中国大陆 IP 处理，将 Play 商店下载 CDN（`redirector.gvt1.com`）解析至北京服务器 `203.208.41.1`，该节点对 APK 下载返回 HTTP 404 并被 `geoip-cn -> DIRECT` 直连规则拦截，导致 Google Play 永远处于 "等待下载中 (Pending)"；同时也会使国内 CDN（如微信图片 CDN `wx.qpic.cn`）被强制解析至异地阿里机房导致访问超时。
- **Google Play 下载组件规则**：
  - `dns.rules` 中必须将 `gvt1.com`、`gvt2.com`、`gvt3.com`、`googleusercontent.com`、`play.googleapis.com` 等置于 `geosite-anti-ad` 等广告拦截规则**之前**走 `dns_proxy`，防止 anti-ad 规则因 gvt1 的广告宿主属性将其判定为广告而返回 `REFUSED`。
  - `inline-google` 中必须补充安卓原生下载器 `com.android.providers.downloads` 与 `android.media`。
- **微信图片与服务防误杀**：
  - 在 `route.rules` 前列加入 `package_name: ["com.tencent.mm"] -> DIRECT`。
  - 在 `dns.rules` 顶层和 `route.rules` 中将 `weixin.qq.com`、`wx.qq.com`、`qq.com`、`qpic.cn`、`qlogo.cn` 等加入直连，避免被 anti-ad 等广告规则拦截。

---

## 4. 守护进程状态机与控制规范
- **待机就绪状态同步**：主循环在 `STATUS_OK`（已联网就绪）循环探测时，必须持续设置 `is_connected = true`，避免 WebUI 与外部接口返回假离线。
- **控制信号中断响应**：任何长休眠或主循环等待分支必须同步轮询并响应 `is_need_reset`、`g_need_stop_now` 和 `g_need_restart_now`，确保网页端重置、停止与重启随时可用。

---

## 5. 分支与工程规范
- **维护重心收敛（铁律）**：全面放弃并停止维护本地 Flutter 原生 APK 版本（受限于系统激进杀后台、Doze 息屏冻结与 VPN 冲突），免 Root 安卓 APK 需求统一在文档与页面中导流至安生同学的开源项目：`https://github.com/anshenglv/ESurfingClient-CVersion-Android-APK`。
- **专精 Magisk 守护模块**：本项目全力维护 **Magisk / KernelSU / APatch 专属 Root 守护进程模块**（`magisk` 分支与模块目录），利用 `wake_lock`、`AID_NET_ADMIN`（GID 3005）与轻量 WebUI 达成 7×24 小时不掉线与透明代理完美共存。
- **CI / CD**：主力维护 `build-magisk-module.yml`。

---

## 6. Windows Clash Verge Rev TUN 模式与校园网防掉认证经验

### 掉认证四大致命根因
1. **心跳服务器漏排除（最致命）**：DialerClient.c 登录成功后获取的 Keep-Url 实测为 http://14.146.227.142:7001/keep.cgi！若 
oute-exclude-address 仅配置了 14.146.227.141/32，每几秒发送一次的心跳包被 TUN 劫持，经由 Wintun 用户态协议栈 NAT 转发破坏了会话与 MAC/IP 绑定，网关 AC 判定心跳超时强行剔除。
2. **认证重定向与 AC 网关漏排除**：校园网 Portal 重定向地址为 net.10000.gd.cn:10001（对应公网 IP 61.140.12.23、125.88.59.131），AC 网关地址为 119.146.175.80。若未排除这些网段，重定向包被海外节点拉取时返回空数据（CURL 52），客户端误以为掉线并无限触发重登。
3. **DoH 探测死锁（CURL 6: DNS 失败）**：
ameserver-policy 若将 
om.miui.com 设为 DoH（https://223.5.5.5/dns-query），在刚开 TUN 或网络握手瞬间，未就绪的 HTTPS 握手会导致 connect.rom.miui.com 解析超时报错，NetClient.c 误判断网。
4. **备用探测 1.1.1.1 阻塞**：电信骨干网封锁对 1.1.1.1:80 的 HTTP 访问。主探测若失败，备用探测 1.1.1.1 会 100% 超时（CURL 28）。

### 终极防掉线配置标准
1. **TUN 排除路由（route-exclude-address）全段覆盖**：
   在 clash-verge.yaml、Merge 与 Script 中确保包含整个 B 类/C 类网段：
   `yaml
   tun:
     enable: true
     stack: gvisor # 或 mixed
     auto-route: true
     strict-route: false # 严禁设为 true
     auto-detect-interface: true
     dns-hijack:
       - any:53
     route-exclude-address:
       - 10.0.0.0/8
       - 100.0.0.0/8
       - 100.64.0.0/10
       - 172.16.0.0/12
       - 192.168.0.0/16
       - 1.1.1.1/32
       - 14.146.0.0/16        # 覆盖 14.146.227.141 认证与 14.146.227.142 心跳 Keep-Url
       - 121.8.0.0/16         # 覆盖 121.8.177.212 备用认证服务器
       - 125.88.59.0/24       # 覆盖 125.88.59.131 Portal 节点
       - 61.140.0.0/16        # 覆盖 61.140.12.23 (enet.10000.gd.cn 认证重定向)
       - 119.146.0.0/16       # 覆盖 119.146.175.80 (WLAN AC 网关)
       - 220.181.104.0/24     # 覆盖 connect.rom.miui.com 主 IP
       - 202.69.4.0/24        # 覆盖 connect.rom.miui.com 备用 IP
       - 18.178.182.212/32
       - 40.81.16.9/32
       - 54.214.98.50/32
       - 173.230.145.114/32
   `
2. **Fake-IP 过滤白名单与纯 UDP DNS 策略**：
   - 在 dns.fake-ip-filter 中加入：
     `yaml
     -  +.cndatacom.com
     - +.cdcc.cn
     - +.189.cn
     - +.gd189.cn
     - +.10000.gd.cn
     - +.gd.cn
     - +.edu.cn
     - connect.rom.miui.com
     - 1.1.1.1
     - 14.146.*
     - 121.8.*
     `
   - **nameserver-policy 必须使用纯 UDP DNS**：
     `yaml
     nameserver-policy:
       +.rom.miui.com: [223.5.5.5, 119.29.29.29]
       +.edu.cn: [223.5.5.5, 119.29.29.29]
       +.cndatacom.com: [223.5.5.5, 119.29.29.29]
       +.cdcc.cn: [223.5.5.5, 119.29.29.29]
       +.189.cn: [223.5.5.5, 119.29.29.29]
       +.gd189.cn: [223.5.5.5, 119.29.29.29]
       +.10000.gd.cn: [223.5.5.5, 119.29.29.29]
       +.gd.cn: [223.5.5.5, 119.29.29.29]
     `
3. **模式与进程规则**：
   - 必须使用 **Rule（规则模式）**。
   - 规则首行置顶：- PROCESS-NAME,ESurfingClient.exe,DIRECT。

### Windows 客户端 (`v2.1.7-r4+`) 部署、认证通道与移动热点 (ICS) 排障规范
1. **本地部署路径与通道铁律**：
   - 本机 Windows 客户端目录：`D:\esurfingclient-v2.1.1-r4-windows-x86_64\`（主程序 `ESurfingClient-2.1.7-r4-windows-x86_64.exe`，以 Windows 服务 `ESurfingClient` 运行 `--role supervisor`）。
   - **通道选择（重要）**：五邑大学校园网（`School Id: 1414`）下，Windows 客户端若配置 `"channel": "windows"`（通道 1），虽然 `win_zsm` 能正常解包获取 Ticket，但向 `http://14.146.227.141:7001/auth.cgi` 提交登录 POST 时会 100% 触发 `CURLcode: 28`（10秒超时无响应）；**必须保持配置为 `"channel": "android"`（通道 3）** 方可秒登录成功。
2. **WebUI 实时网速与热点控制桥接 (`tools/windows-network-panel`)**：
   - 上游 `v2.1.7-r4` 的 Release 压缩包漏打包了仓库根目录的 `tools/windows-network-panel/`，导致前端 `hotspot.js`（请求 `http://127.0.0.1:18889`）与 `traffic.js`（轮询 `portal/assets/traffic.json`）报错不可用。
   - **WinRT 运行时限制**：`TrafficCollector.ps1` 与 `HotspotBridge.ps1` 依赖 `.NET Framework` 的 `ContentType=WindowsRuntime` 绑定（`NetworkOperatorTetheringManager`），**必须显式使用系统自带的 Windows PowerShell 5.1 (`$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe`) 启动**，不可直接用 `pwsh` 7 执行（这是唯一允许调用 `powershell.exe` 5.1 的特殊场景）。
   - 本地已补齐 `D:\esurfingclient-v2.1.1-r4-windows-x86_64\tools\windows-network-panel\` 并配置一键后台启动脚本 `启动校园网与网速.cmd`。
3. **Windows 移动热点手机连不上 / 卡“获取 IP 地址” (`169.254.x.x`) 根因与秒修方案**：
   - **故障特征**：移动热点显示“已开启 (`On`)”，手机能搜到热点并完成 WPA2 关联（`WLAN-AutoConfig` Event ID `20019`），但约 18 秒后断开重连；电脑执行 `ipconfig` 发现热点虚拟网卡（`本地连接* 4` / `Microsoft Wi-Fi Direct Virtual Adapter`）IP 为 `169.254.x.x/16` 而非标准的 `192.168.137.1/24`，且 `HNetCfg.HNetShare` 显示所有网卡 `SharingEnabled: False`。
   - **根因**：热点此前绑定在旧的无线 Profile 上，或上联网卡（`以太网`）在客户端重启/重认证期间短暂失去 Internet 连通性，导致 Windows `SharedAccess` (ICS) 自动解绑了 NAT/DHCP 共享，但未关闭 Wi-Fi 热点广播。
   - **一键重置绑定命令**：调用 `powershell.exe` 5.1 获取当前具有公网连通性的 `GetInternetConnectionProfile()`，对该 Profile 的 `NetworkOperatorTetheringManager` 先执行 `StopTetheringAsync()` 等待状态变为 `Off`，再执行 `StartTetheringAsync()`，即可让 ICS 重新将 `192.168.137.1/24` 绑定至热点虚拟网卡并恢复手机 DHCP 分配。

---
## 7. 3x-ui 面板升级、Xray Reality 与 Sub-Store 避坑经验

### 1. 3x-ui (v3.8.5+) 与 Xray 内核版本兼容性（电脑 Mihomo + 手机 sing-box 共存）
- **陷阱一（`minClientVer: "1.0.0"` 导致全端 Timeout）**：
  - 升级 3x-ui 面板或在面板中保存 Reality 节点时，若 `realitySettings.minClientVer` 被设为 `"1.0.0"`，由于 `Mihomo`（Clash Verge）和 `sing-box` 在 Reality 握手 `SessionID` 中发送的客户端版本号均为 `[0, 0, 0]`（`0.0.0`），服务端会判定 `0.0.0 < 1.0.0` 并将其作为非法探测全部丢入 fallback 回落域名，导致 **100% 握手超时**。
  - **铁律**：服务端 `/etc/x-ui/x-ui.db` 的 `inbounds` 中，`minClientVer` 和 `maxClientVer` **必须保持为空字符串 `""`**。
- **陷阱二（`Xray 26.x` 后量子 `X25519MLKEM768` 导致手机 `sing-box 1.12.x` 报 `reality verification failed`）**：
  - `Xray 26.9.9+` 默认使用后量子 `X25519MLKEM768` 派生 Reality 临时证书签名密钥，而手机端 `sing-box 1.12.17` 仅支持标准 `X25519` 验签，会导致手机端报 `reality verification failed`。
  - **铁律**：服务端统一保持 **Xray `v25.3.6`** 内核（面板保持 `3x-ui 3.8.5` 即可），并在 `/etc/x-ui/x-ui.db` 的 `settings.xrayTemplateConfig` 中将内部 API 协议 `"protocol": "tunnel"` 设为全版本通用的 `"protocol": "dokodemo-door"`。同时客户端（Clash / sing-box）保持 `"fingerprint": "chrome"` 且**不开启** `support-x25519mlkem768`，即可让电脑与手机同时满速连通。

### 2. Clash (`fake-ip`) DNS 与直连海外 CDN 避坑
- **禁止在 `fake-ip` 模式下配置无法直连的 `fallback` (`1.1.1.1` / `8.8.8.8`) + `fallback-filter (geoip: CN)`**：
  - 在 `fake-ip` 模式下，仅走 `DIRECT` 的规则会在本地解析真实 IP。若启用了 `fallback-filter (geoip-code: CN)`，当直连微软或 Spotify 音频 CDN 时，阿里 DoH (`223.5.5.5`) 返回的海外 Anycast IP（`GeoIP != CN`）会被当成污染直接丢弃，并强行等待校园网下被墙/被劫持的 `1.1.1.1` / `8.8.8.8`，最终引发 `dns resolve failed: couldn't find ip`。
- **禁止宽泛直连 `DOMAIN-SUFFIX,akamaized.net,DIRECT`**：
  - Spotify 音频流直连仅能匹配专属域名（如 `audio-ak-spotify-com.akamaized.net`），切勿将整个 `akamaized.net` 设为 `DIRECT`，否则会误伤微软官网/登录页静态资源。

### 3. 六台核心 VPS 全球拓扑、SSH 凭据与 Sub-Store 接口规范
- **服务器清单与架构**：
  1. **香港 (`40.81.16.9`)**：`aarch64` (`arm64`)，`ssh -i "C:\Users\LFQ\Downloads\gha_key.pem" azureuser@40.81.16.9`（Azure East Asia 香港，注意用户名为 `azureuser`，内核二进制为 `/usr/local/x-ui/bin/xray-linux-arm64`，面板端口 `2000`，订阅端口 `2096`，Reality 端口 `443`。**现为 Sub-Store 与 Caddy 核心中枢主机**，HTTPS 端口 `3002`，直连延迟 84ms）。
  2. **香港 GCP (`34.96.219.57`)**：`amd64`，`ssh -i "C:\Users\LFQ\.ssh\id_ed25519" root@34.96.219.57`（Google Cloud 香港 `asia-east2`，2核4G AMD EPYC，直连延迟仅 14~53ms 极速。部署 **原生 BBR + `fq`**、64MB 极限缓冲、Xray `v25.3.6` Reality 443 `gateway.icloud.com`、Cloudflare WireGuard WARP 出站精准分流，面板端口 `2000`，订阅端口 `2096`，面板账号 `admin` / `ironjhin_gcp_2026`。**⚠️ 注意生命周期：2026-10-23 起仅剩 36 天，预计 2026-11-28 前后到期，到期前需删除停机防止扣费**）。
  3. **新加坡 GCP (`34.21.202.113`)**：`amd64`，`ssh -i "C:\Users\LFQ\.ssh\id_ed25519" root@34.21.202.113`（Google Cloud 新加坡 `asia-southeast1`，Debian 12 Bookworm，`e2-micro` 2核1G + 2GB Swap。部署 **原生 BBR + `fq`**、64MB 极限缓冲、3x-ui v2.6.2、Xray `v25.3.6` Reality 443 `gateway.icloud.com`，短 ID `c34b5e9b`，公钥 `CUf2SZuJSWGCAGbVoi5ZPDXolvnbeWxjzw-OpUOv62c`。国内广东电信直连仅 **54ms** 极速！面板端口 `2000`，面板账号 `admin` / `ironjhin_gcp_2026`。**⚠️ 注意生命周期：2026-10-23 起剩余 79 天，预计 2027-01-10 前后到期，已配置 1150GB 自动断流硬上限安全锁**）。
  4. **美国俄勒冈 (`54.214.98.50`)**：`amd64`，`ssh -i "C:\Users\LFQ\Downloads\LightsailDefaultKey-us-west-2.pem" ubuntu@54.214.98.50`（AWS Lightsail 俄勒冈 `us-west-2`，内核统一为 `/usr/local/x-ui/bin/xray-linux-amd64` `v25.3.6`，面板端口 `2000`，订阅端口 `2096`，Reality 端口 `443`。纯 IPv4 WARP 出站秒过 CF）。
  5. **日本东京 (`18.178.182.212`)**：`amd64`，`ssh -i "C:\Users\LFQ\Downloads\LightsailDefaultKey-ap-northeast-1.pem" ubuntu@18.178.182.212`（AWS Lightsail 东京 `ap-northeast-1`，内核统一为 `/usr/local/x-ui/bin/xray-linux-amd64` `v25.3.6`，面板端口 `2000`，订阅端口 `2096`，Reality 端口 `443`，纯 IPv4 WARP 出站。已完全替换原 `13.112.159.221`，延迟 124ms）。
  6. **美国加州 Fremont (`173.230.145.114`)**：`amd64`，`ssh -i "C:\Users\LFQ\.ssh\id_ed25519" root@173.230.145.114`（Akamai Connected Cloud 4核8G，**5 Gbps 物理端口，5TB 月流量大池**。已部署 **原生 BBR + 纯 `fq` 队列**、64MB 极限缓冲、Xray `v25.3.6` Reality 443 `gateway.icloud.com`，国内直连延迟 159-170ms，0% 丢包。作为超大流量 4K 与高速主力机）。
- **Sub-Store 远程文件同步规范**：
  - Clash Verge 主订阅对应的 Sub-Store 接口为：`https://sub.ironjhin.us.ci:3002/api/wholeFile/%E6%97%A5%E6%9C%AC%2B%E9%A6%99%E6%B8%AF%2B%E7%BE%8E%E5%9B%BD`。
  - Sub-Store 网页控制台与 HTTPS 入口为：`https://sub.ironjhin.us.ci:3002/`（由 Azure 香港 Caddy 反代至本地 3000/3001，配置 Let's Encrypt 正式证书与 HTTP/3 支持）。
  - 提交更新时必须确保 `payload.process = @()`（清空脚本覆盖器），防止旧的 `Script Operator` 覆盖 `payload.content`。
- **Clash Verge Rev 内核热重载与延迟测试**：
  - 从 `C:\Users\LFQ\AppData\Roaming\io.github.clash-verge-rev.clash-verge-rev\clash-verge.yaml` 动态读取 `external-controller-pipe`（如 `\\.\pipe\verge-mihomo-sidecar-release-<hash>`），通过 Named Pipe 调用 `PUT /configs?force=true` 重载配置，以及 `GET /group/%E8%87%AA%E5%8A%A8%E9%80%89%E6%8B%A9/delay?url=http%3A%2F%2Fwww.gstatic.com%2Fgenerate_204&timeout=5000` 验证节点连通性。
- **GCP 香港中转（`dialer-proxy` 链式代理）与 Xray `sniffing` 避坑铁律**：
  - **核心机制**：通过在 Mihomo（Clash Verge / 手机 Surfing）节点上配置 `dialer-proxy: "🇭🇰 香港 GCP"`，客户端先与 GCP 建立外层 VLESS-Reality 连接，再在隧道内同日本（东京 Lightsail）和美国（俄勒冈 Lightsail / 加州 Akamai）建立端到端加密的内层连接，日本延迟由 564ms 暴降至 266ms 且不需在 GCP 额外开放多余转发端口。
  - **致命陷阱（`sniffing` 劫持内层 SNI 导致 `REALITY Authentication: false`）**：若 GCP Xray 入站启用 `sniffing` 且 `routeOnly: false`（默认值），当内层 Reality 发出 SNI `gateway.icloud.com` 时，Xray 会强行将目标地址从真正的目标节点 IP（如 `18.178.182.212`）篡改为 Apple 官方服务器 IP，导致内层握手回落至真苹果服务器引发验签失败。**铁律**：作为中转跳板的 Xray 入站 sniffing 必须配置 `"routeOnly": true`（仅用于分流匹配，禁止重写真实目的 IP）。

### 4. 手机端 `Surfing`（基于 `Mihomo` 内核，已替代旧 `Box4Magisk` / `sing-box`）运维与远程命令规范
- **核心变更（2026-09-27）**：
  - 手机端已弃用 `Box4Magisk`（`sing-box`），全面切换为 **`Surfing`**（基于 **`Mihomo` / `Clash.Meta`** 内核，配置与运行目录位于 `/data/adb/box_bll/`）。
  - **订阅与配置完全统一**：由于电脑端 `Clash Verge Rev` 与手机端 `Surfing` 现均使用 `Mihomo` 内核，手机端可直接共用 Sub-Store 的 ClashMeta YAML 订阅（`http://56.155.64.207:3000/api/file/%E6%97%A5%E6%9C%AC%2B%E9%A6%99%E6%B8%AF%2B%E7%BE%8E%E5%9B%BD`），且两端均原生支持后量子 `X25519MLKEM768`。
  - **校园网共存要点与完整配置规范**：
    - **`box.config` (`/data/adb/box_bll/scripts/box.config`)**：
      - 必须配置 `gid_list=(3005)`，确保 `box.iptables` 生成 `BOX_LOCAL` 针对 `GID 3005`（`AID_NET_ADMIN`）的直连豁免（`UID 0 + GID 3005 -> RETURN`），让守护进程 `esurfingd` 的流量在被 TPROXY 标记之前直接出站。
      - 在 `user_packages_list` 中确认包含 `"0:com.cndatacom.campus.cdccportalgd"` 与 `"0:com.example.esurfing_client"`。
      - 在 `intranet` 中保持校园网直连 IP：`100.0.0.0/8`、`220.181.104.183/32`、`14.146.227.141/32`、`121.8.177.212/32`、`1.1.1.1/32`。
    - **`box.iptables` (`/data/adb/box_bll/scripts/box.iptables`)**：
      - 在 `CLASH_DNS_LOCAL`（NAT 与 Mangle）中必须对 `gid_list` 执行 `RETURN`，防止未认证时本地守护进程发出的 DNS 请求被重定向到未联网的 Clash 内置 DNS 导致超时卡死。
      - 确保脚本换行符严格为 `LF`（避免 Windows CRLF 导致 `/system/bin/sh: ... No such file or directory`）。
    - **`config.yaml` (`/data/adb/box_bll/clash/config.yaml`)**：
      - 在 `rules:` 顶部（`DST-PORT,853,DNS连接` 之后）显式置顶校园网直连规则：
        - `PROCESS-NAME,esurfingd,🌐 本机·本地直连`
        - `PROCESS-NAME,com.example.esurfing_client,🌐 本机·本地直连`
        - `PROCESS-NAME,com.cndatacom.campus.cdccportalgd,🌐 本机·本地直连`
        - `DOMAIN,connect.rom.miui.com,🌐 本机·本地直连`
        - `DOMAIN-SUFFIX,rom.miui.com/cndatacom.com/cdcc.cn/189.cn/gd189.cn/edu.cn,🌐 本机·本地直连`
        - `IP-CIDR,220.181.104.183/32 / 14.146.227.141/32 / 121.8.177.212/32 / 1.1.1.1/32 / 100.0.0.0/8,🌐 本机·本地直连,no-resolve`
      - 在 `dns.direct-nameserver` 中加入 `- system`，以便直接通过 Android 系统/DHCP 分配的网关 DNS 解析直连域名。
- **PowerShell 跨平台命令传输铁律**：
  - 在 Windows PowerShell 中通过 `adb shell su -c` 或 `ssh` 执行包含引号、管道 `|`、`&` 或 Python/SQLite 的复杂命令时，**必须先在本地转为 Base64 字符串**，再通过 `echo <b64> | base64 -d | sh`（或 `sudo python3`）执行，彻底杜绝引号吞噬与参数截断。

### 5. AWS Lightsail 节点 Cloudflare 人机验证（Turnstile / 5秒盾）与 Xray 内置 WireGuard WARP 分流规范
- **根因分析**：
  - AWS Lightsail 数据中心网段（ASN 16509）被 Cloudflare 判定为高风险爬虫/数据中心 IP，访问 Cloudflare CDN 托管或开启 Bot Management / Turnstile 的网站（如 `linux.do`、OpenAI、Claude、Turnstile 验证码）时会 100% 触发 HTTP 403 / 5秒盾拦截（`cf-mitigated: challenge`）。
- **避坑铁律**：
  - **严禁安装系统级 `cloudflare-warp` (`warp-svc`) 守护进程**：在 512MB RAM 的 Lightsail 实例上，`warp-svc` 会自动接管 `0.0.0.0/0` 默认路由导致 SSH 外部连接彻底超时失联；同时其常驻进程与 GUI 助手会迅速撑爆内存引发 OOM 宕机。
  - **Reality 伪装 SNI 切勿指向 `www.cloudflare.com`**：若外层 Reality 使用 `www.cloudflare.com`，访问内层 Cloudflare 网站时会因 Vision 检查和握手冲突导致 `curl (35) schannel: failed to receive handshake` 挂死。全节点统一保持 `gateway.icloud.com`。
- **最佳生产方案：Xray 原生用户态 WireGuard WARP 出站**：
  - Xray v25+ / v26+ 原生内置 `protocol: "wireguard"` 出站（基于用户态 gVisor TUN / 内核 TUN），**0 额外守护进程，0 内存膨胀，完全不触碰系统默认路由表**。
  - 通过 Cloudflare Client API 注册 WARP 独立密钥对与内网 IP（`172.16.0.2/32`）。
  - 在 Xray `routing.rules` 中设置精准分流（**切勿配置全局 `geoip:cloudflare`**，否则全球 20% 采用 CF CDN 的普通网站与大文件下载会被无差别塞入免费 WARP 导致严重降速）：
    ```json
    {
      "domain": [
        "geosite:openai",
        "domain:challenges.cloudflare.com",
        "domain:turnstile.cloudflare.com",
        "domain:cloudflare.com",
        "domain:linux.do"
      ],
      "outboundTag": "warp",
      "type": "field"
    }
    ```
  - **实现效果**：常规所有网站（YouTube、Google、Microsoft、GitHub、下载等）走 AWS 原生 1Gbps 千兆公网出站（满速带宽）；仅 OpenAI、Turnstile 验证码及特定 5 秒盾挑战流量精准分流至 WARP（`warp=on`），既秒过风控，又绝不牺牲下载带宽。
  - **TUN 环路防护**：在本地 Clash Verge 的 `tun.route-exclude-address` 与规则集最顶层必须将 4 台 VPS 节点的公网 IP 声明为 `DIRECT,no-resolve`，彻底防止代理回环与 SSH 卡死。
  - **Lightsail 512MB 内存加固**：必须预先创建 1024MB Swap 文件（`/swapfile`），避免面板与编译操作触发 Linux OOM Killer。
  - **WARP 纯 IPv4 出口优化**：CF 人机验证与 Turnstile 仅判定 IP 信誉与 WARP 消费者池属性（`warp=on`），与 IPv6 无关。WireGuard 出站仅配置 `address: ["172.16.0.2/32"]`（剔除 IPv6 `2606:.../128`），可彻底消除双栈 DNS 竞速延迟与国内校园网 IPv6 丢包，出站统一分配干净利落的 `104.28.x.x` IPv4 地址。
  - **AWS Lightsail 实例 Xray 内核与系统网络加固**：
    1. 全节点必须安装 `Xray v25.3.6` 二进制，严禁使用 26.x（防止 MLKEM768 导致客户端验签失败）。
    2. Lightsail Ubuntu 默认缺少外部 IPv6 连通，必须配置 `net.ipv6.conf.all.disable_ipv6 = 1`，并将 Xray `dns.servers` 设为 `["localhost"]`，防止 Reality 伪装域名（如 `gateway.icloud.com`）解析返回 AAAA 导致握手回落到未就绪的目标。
    3. **网卡 MTU 9001 超大帧与队列避坑**：Lightsail 默认分配 `mtu 9001`（Jumbo Frame）且队列为 `mq -> fq_codel`。在跨海公网（115ms+ RTT）下，`fq_codel` 的 5ms 目标延迟会误判拥塞疯狂丢包摧毁 BBR，且 9001 MTU 引发 PMTU 黑洞。必须强制配置 `ip link set dev ens5 mtu 1500`、`net.core.default_qdisc = fq`、`tc qdisc replace dev ens5 root fq` 以及 `tcp_rmem/wmem` 64MB 极限缓冲区与 `tcp_mtu_probing = 1`。
    4. **拥塞控制架构演进（从 TCP Brutal 回归纯血 BBR + FQ，2026-10-16）**：
       - **Brutal 致命缺陷**：Brutal 是固定盲发机制，当设定 300 Mbps 时，若客户端处于校园网限速（如 50~60 Mbps Policer）或 163 晚高峰瓶颈，网关会硬件直接抹除多余报文，导致数学上必现 `(300-60)/300 = 80%` 极端物理丢包，触发严重 TCP 重传风暴与队头阻塞，视频播放彻底卡死。
       - **现行标准**：全节点已彻底注销停用 `brutalctl-rules.service/timer` 并执行 `brutalctl flush`，统一回归 **Linux 原生 BBR (`net.ipv4.tcp_congestion_control = bbr`)** + **Fair Queueing (`net.core.default_qdisc = fq`)**，由 BBR 自动贴合探测链路真实瓶颈，丢包率压制至最低。
  - **Lightsail 新加坡（`47.130.x.x`）国际骨干丢包避坑**：
    - `47.130.x.x` 网段经 NTT 至中国电信 163 骨干网（`202.97.66.190`）在高峰期存在约 40% 物理丢包，导致 TCP SYN 重传引发延迟与假死。
    - 应对策略：(1) 在 Lightsail 控制台 Networking 免费解绑并重新分配 Static IP（抽到 `18.140.x.x`、`18.141.x.x` 或 `13.250.x.x` 即可避开该拥堵路由）；(2) 或利用香港 Azure（`40.81.16.9`，45ms 直连新加坡，0 丢包）作为 `dialer-proxy` 链式前置。

### 6. Akamai Fremont 与各海外节点网络栈调优规范
- **内核网络栈标准基线**：
  - 队列调度器统一采用纯 `fq`（`tc qdisc replace dev eth0 root fq`，避免 `fq_codel` 5ms 误判）。
  - MTU 1500，`tcp_mtu_probing = 1`，缓冲区配置 64MB 极限 `tcp_rmem / tcp_wmem`。
  - 全节点停用 Brutal 强发路由，保持纯血 BBR 自动拟合。
- **纯 IPv4 出站与永久禁用 IPv6 规范（2026-10-15）**：
  - Akamai Fremont 默认分配了 `2600:3c01::...` IPv6 地址，导致双栈 DNS 竞速时出站优先走 IPv6，引发网站 IP 归属地偏差或校园网丢包。
  - 已通过 `/etc/sysctl.d/99-disable-ipv6.conf` 注入 `net.ipv6.conf.all/default/lo.disable_ipv6 = 1`，彻底停用内核 IPv6 栈并重启 Xray。
  - 当前出站 100% 锁定纯净美西 IPv4（`173.230.145.114`），开机自动永久生效。

### 7. 全球四节点流量监控、配额熔断与桌面一键看板规范
- **各云厂商流量计费规则**：
  - **Akamai / Linode**：首月按创建剩余天数等比例（Prorated）分配流量池（如中旬创建获 ~3371 GB），每月 1 日零点重置为完整 5000 GB (5 TB)。
  - **Azure 香港 (`40.81.16.9`)**：每月严格 100 GB 免费出站额度，仅允许作为中枢与分流控制，严禁用作主力下载。
  - **AWS Lightsail**：每月 1 TB ~ 2 TB 出站额度。
- **3x-ui 面板配额熔断**：
  - 在面板 Inbounds 设置中，可为入站或客户端指定 `Total GB` 流量上限。达到阈值时内核自动熔断停用端口，防止超出免费池。
- **并发监控看板实现**：
  - 本地 Python 脚本 `C:\Users\LFQ\Desktop\esurfing_flutter\check_vps_traffic.py` 采用 `ThreadPoolExecutor` 并发读取四台 VPS 的 `/etc/x-ui/x-ui.db` 底层计数器，2 秒内完成探测并生成彩色进度条看板。
  - 桌面快捷入口：`C:\Users\LFQ\Desktop\查询节点流量.bat`。
  - 服务端守护进程：Fremont 已部署 `vnstat`，支持 `vnstat -d`、`vnstat -m`、`vnstat -l`。
