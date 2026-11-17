# 天翼校园网认证客户端 (Magisk / KernelSU 专属守护进程)

> [!NOTE]
> ☕ **关于本项目**：本项目纯属“氛围编程”的产物，作者是个机械佬、本质上不太懂代码，很多功能和优化也是边摸索边借助 AI 辅助写出来的。若遇到 Bug 或设计不周之处请大家多多包涵！  
> 💬 **问题反馈与交流**：有任何使用疑问或 Bug 反馈，欢迎提交 Issue 或直接联系开发者邮箱：[2292219067@qq.com](mailto:2292219067@qq.com)。  
> 📢 **版本维护说明（重要）**：作者已全面转向并**只维护 Magisk / KernelSU / APatch 专属 Root 守护进程模块**（开机即连、极致省电、永不断流）。若您需要**免 Root 的原生 Android APK 客户端**，强烈推荐直接使用安生同学精心维护的项目：👉 **[anshenglv/ESurfingClient-CVersion-Android-APK](https://github.com/anshenglv/ESurfingClient-CVersion-Android-APK)**。

专为 Android Root 平台（Magisk / KernelSU / APatch）设计的高可用广东天翼校园网认证守护进程。核心由纯 C 语言高并发引擎驱动，具备超低内存占用（仅 1~2 MB）、开机即连、无感常驻、自带 WebUI 控制台，并与 Surfing / Mihomo 透明代理完美共存。

---

## 🌟 核心特性

- **⚡ 纯 C 驱动，极速低耗**：底层认证、心跳保活与加解密引擎基于纯 C 语言与 libcurl 静态构建，无庞大运行时依赖，模块守护进程仅占 **1~2 MB 内存**。
- **🔄 同步上游最新协议引擎 (v2.3.1-r5 / 模块 v1.1.73)**：
  - **认证防风控与心跳韧性**：连续两次 `302` 二次确认防网关抖动误踢、60 秒内登录频控锁 35 分钟（尾档退避 35 分钟避开整点锁）；心跳区分网络不通 (`HB_NET_FAIL`) 与服务端拒绝 (`HB_PROTO_FAIL`) 并采用 `1/2/4/8/16/30s` 指数退避重试。
  - **自定义联网探测 (`probe_hosts`)**：支持最多 14 路固定 IPv4 并发探测，缺失自动补全写回配置文件，Portal 与 KernelSU WebUI 均支持可视化编辑。
  - **单调时钟防混乱与状态收拢**：子进程退避、心跳间隔、运行时间与网速采样全面采用单调时钟（`CLOCK_MONOTONIC`），彻底免疫息屏休眠、NTP 校时跳变；配置保存与应用基于 `.apply` 标记解耦热重载。
  - **多进程单实例锁与异常断电持久化**：新增 `main` / `web` / `auth-N` 文件锁防双开互踢；具备会话现场归档（`.logout`），异常强杀或断电后下次启动自动补登出。
- **📱 专注 Root 守护进程模块**：
  - **Magisk / KernelSU / APatch 专属**：开机无感静默认证、后台永久驻留、内置新版响应式 Bento 风格 KernelSU WebUI（100% 离线零外链、深浅双主题、现代着色日志终端）与桌面管理端 (`http://127.0.0.1:8888`)。
  - **免 Root APK 跳转**：未 Root 手机用户请直接使用推荐的独立客户端 👉 [anshenglv/ESurfingClient-CVersion-Android-APK](https://github.com/anshenglv/ESurfingClient-CVersion-Android-APK)。
- **🛡️ 透明代理完美共存**：
  - 模块守护进程开机自动获取 `AID_NET_ADMIN` (`GID 3005`) 权限，原生命中 `Surfing` / `Mihomo` / `Clash.Meta` / `sing-box` / `Box4Magisk` 的首条直连豁免规则，彻底防止 TPROXY 误劫持与死循环断流。
  - 自动申请内核 `wake_lock`，有效抵御系统深度 Doze 睡眠冻结心跳。

---

## 🆚 运行形态对比与推荐

| 维度 | Android APK 独立客户端（推荐 anshenglv 版） | Magisk / KernelSU 守护进程版（本项目主维护） |
| :--- | :--- | :--- |
| **项目地址** | [anshenglv/ESurfingClient-CVersion-Android-APK](https://github.com/anshenglv/ESurfingClient-CVersion-Android-APK) | 本项目仓库（[Releases](https://github.com/Ironjhin/EsurfingClient_Android/releases?q=magisk)） |
| **运行权限** | 普通用户应用（免 Root） | 系统 Root 守护进程 (`root:3005`) |
| **内存占用** | 约 30 ~ 60 MB | **约 1 ~ 2 MB**（纯 C 二进制 `esurfingd`） |
| **交互界面** | 原生 Android App 界面 | 内置轻量 WebUI + 桌面专用管理图标 |
| **保活能力** | 前台通知服务 + 无障碍服务辅助保活 | **Root 级永驻**，系统杀后台机制完全免疫 |
| **开机自启** | 依赖系统自启管理与广播唤醒 | **系统开机阶段挂载启动**，亮屏前已联网 |
| **适用人群** | 未解锁 Bootloader、免 Root 日常使用 | 已 Root 玩家、需要极致省电与无感挂机体验 |

---

## 🚀 下载与安装

### 1. Magisk / KernelSU / APatch 模块版 (需 Root · 本项目主维护)
1. 前往仓库 [Releases 页面](https://github.com/Ironjhin/EsurfingClient_Android/releases?q=magisk)。
2. 下载最新版 `esurfing-daemon-arm64-v8a.zip`。
3. 打开 **Magisk Manager**、**KernelSU Manager** 或 **APatch** $\to$ 「模块」 $\to$ 「从本地安装」选择该 zip 包。
4. 安装完成重启手机后：
   - 桌面会自动生成 **ESurfing** Web 控制端应用图标。
   - 也可直接在手机浏览器中访问 `http://127.0.0.1:8888/` 进行配置管理。
   - KernelSU / APatch 用户可在管理器模块卡片中直接点击 **WebUI** 按钮或 **Action** 按钮免重启启停服务。

### 2. Android APK 原生版 (免 Root 用户)
> [!TIP]
> **免 Root 用户推荐**：本项目已停止维护自编译 APK。如果您没有解锁 Bootloader 或未 Root 设备，请直接前往安生同学的开源仓库下载最新 APK：  
> 🔗 **[anshenglv/ESurfingClient-CVersion-Android-APK](https://github.com/anshenglv/ESurfingClient-CVersion-Android-APK)** (功能完善、体验优秀、持续跟进)

---

## 🛠️ 底层引擎演进与核心修复 (v2.3.1-r5)

本项目底层 C 引擎持续跟进上游 [BadGhost520/ESurfingClient-CVersion](https://github.com/BadGhost520/ESurfingClient-CVersion) 的最新更新，并在移动端环境下做了深度优化与排坑：

| # | 问题 / 功能 | 诱因与现象 | 修复与改进实现 |
|---|---|---|---|
| **1** | **防风控与心跳指数退避** | 网关抖动单次 302 误踢触发重登、频繁登录易撞服务端 30 分钟锁定窗口 | 连续两次 `302` 确认才重认证；60 秒登录满 2 次暂停 35 分钟；心跳区分网络/协议失败并按 `1/2/4/8/16/30s` 退避 |
| **2** | **自定义探测 (`probe_hosts`)** | 部分校园网环境默认探测域名/IP 不可达或需人工指定直连探针 | 支持最多 14 路固定 IPv4 并发探测，缺失自动补全写回配置文件，支持双端 Web 可视化编辑 |
| **3** | **通道锁定与多进程单实例锁** | Android 端使用 Windows 通道易登录 POST 超时；无 `/tmp` 导致单实例锁失效 | 默认锁定 `android` (通道 `3`)；锁路径适配 `/data/adb/esurfing/esurfingclient-*.lock`；绑定 `SO_MARK` 失败直接放弃防串线 |
| **4** | **PID / WakeLock 生命周期修复** | 查询模式或重复启动误删运行中 PID 文件；停止服务后 `wake_lock` 未释放无法深度休眠 | 仅主守护进程抢锁成功后写 PID 与持锁，正常退出及 `action.sh`/`uninstall.sh` 严格校验进程归属并释放 `wake_unlock` |
| **5** | **全链路单调时钟与信号安全** | NTP 校时跳变导致退避/uptime/网速计算错乱；`SIGUSR1` 非原子标志属 UB | 全面采用 `CLOCK_MONOTONIC` (`get_steady_tm_ms()`)；异步信号标志统一为 `volatile sig_atomic_t` |
| **6** | **Web 后端死锁与内存加固** | `WebLogFiles` 脏缓冲与内存泄漏；禁用配置后 `/api/applyConfigs` 回 `503` 死锁；`/api/restart` 端口冲突 | 栈缓冲重写 `logFn`；放通禁用后热重载；按 `bootId` 区分新旧实例；修复 `mark` 丢失并补齐线程包装体释放 |
| **7** | **KernelSU WebUI 与 APK 修复** | 旧版前端缺高级配置/主题/终端过滤；桌面 WebView APK 在 Android 9+ 禁明文 HTTP | 重构 100% 离线零外链 Bento WebUI；补齐 `usesCleartextTraffic="true"` 与返回键导航；修复 `build.sh`/`service.sh` 权限与漏拷 |

---

## 📝 更新日志

完整版本变更请查看 **[CHANGELOG.md](CHANGELOG.md)**。

### v1.1.73 (Core v2.3.1-r5)
- **多维自动日志轮转淘汰引擎**：新增 `log_max_files`（默认 `5`，范围 `0..100`）、`log_max_days`（默认 `3`，范围 `0..365`）与 `10 MB` 历史归档总体积兜底上限；启动、轮转及退出时自动清理超限旧 `.log` 归档（`lstat` 精准过滤防误删、未同步 NTP 时跳过按天淘汰），并将默认日志等级优化为 `INFO (4)`。
- **原位截断安全清空日志 API (`POST /api/logs/clear`)**：支持 `all`（清空归档 + 原位 `truncate` 当前 `run.log`，保障多进程 `O_APPEND` 句柄不失效）与 `archived`（仅清理历史归档），返回释放文件数与字节数。
- **双端 WebUI 存储统计与清理升级**：KernelSU Bento WebUI 与 8888 原生 Portal 均新增日志存储占用统计、一键「清理日志」模态确认弹窗及 `log_max_files` / `log_max_days` 参数编辑校验。

### v1.1.72 (Core v2.3.1-r5)
- **同步上游 `v2.2.0-r5` → `v2.3.1-r5`**：连续两次 `302` 确认与 60s 登录频控防锁定、心跳区分网络/协议失败指数退避、最多 14 路 `probe_hosts` 自定义并发探测、`main`/`web`/`auth-N` 单实例锁、`SO_MARK` 失败丢弃、`.apply` 热重载解耦、`States` (`cfg_t`) 重构与 `VERBOSE → TRACE` 更名。
- **KernelSU WebUI 全面重构**：离线零外链 Bento 卡片设计、深浅双主题切换、呼吸灯、密码显隐、自定义弹窗、`probe_hosts` 折叠面板及防 XSS 着色日志终端。
- **模块稳定性与脚本修复**：锁定 `android` 默认通道、修复 PID 误删与 `wake_lock` 泄漏、全链路切换单调时钟、修复 `WebLogFiles` / `/api/applyConfigs` / `/api/restart` / `GET /api/getConfigs` 多项后端缺陷，修复 `build.sh` / `service.sh` / `action.sh` / `uninstall.sh` 与 WebView APK 明文加载问题，新增 `.gitattributes` 锁定 LF 换行符。

---

## 🌐 透明代理（Surfing / Mihomo / Box4Magisk）共存配置指南

若你的 Android 设备同时运行透明代理（如基于 Mihomo/Clash.Meta 内核的 **Surfing**，或 **Box4Magisk**）：

1. **GID 3005 直连豁免（最关键）**：
   - 守护进程 `esurfingd` 启动时已自带 `GID 3005`。
   - 在 Surfing 的 `box.config` (`/data/adb/box_bll/scripts/box.config`) 中配置：
     ```ini
     gid_list=(3005)
     ```
   - 确保 iptables 规则命中 `UID 0 + GID 3005 -> RETURN` 直连，避免未认证时的认证包被 TPROXY 拦截死锁。
2. **应用过滤排除名单**：
   - 在代理排除包名列表（`user_packages_list` 或 `exclude.list`）中加入：
     - `com.example.esurfing_client`（Flutter 版应用）
     - `com.cndatacom.campus.cdccportalgd`（官方客户端）
3. **校园网认证服务器与内网放行**：
   - 将以下校园网网段加入直连路由与 DNS 直连白名单：
     - 探测地址：`connectivitycheck.platform.hicloud.com`、`connect.rom.miui.com`、`183.61.185.93/32`、`125.88.255.53/32`、`202.69.4.32/32`、`220.181.104.183/32`、`1.1.1.1/32`
     - 认证与心跳服务器：`14.146.227.141/32`、`14.146.227.142/32`、`121.8.177.212/32`、`100.0.0.0/8`
     - 域名后缀：`+.cndatacom.com`、`+.cdcc.cn`、`+.189.cn`、`+.gd189.cn`、`+.edu.cn`

---

## 🔍 常见运行状态判定

打开 WebUI 网页控制台或管理界面后，日志面板会输出当前网络状态，可据此判断网关环境：

- **`已连接至互联网 / Status code: 204`**：
  - 说明网络已连通，或者当前网关已放行本机物理 MAC。若此时不需要再次拨号，系统将转为低频心跳待命状态。
- **`需要认证 / Status code: 302`**：
  - 说明网络流量被校园网 Portal 拦截，客户端会自动提取 Portal 认证配置、动态拉取 ticket、解包算法模块并完成登录。
- **`已认证登录 / 发送心跳包`**：
  - 认证成功并已建立会话，心跳定时器将在租约周期内周期性保活，维持网络通畅。

---

## 🤝 开源致谢与引用

本项目的实现高度依赖开源社区的无私贡献：

- **核心协议与算法来源**：[BadGhost520/ESurfingClient-CVersion](https://github.com/BadGhost520/ESurfingClient-CVersion)（遵循 Apache-2.0 协议）
- **推荐免 Root 安卓客户端**：[anshenglv/ESurfingClient-CVersion-Android-APK](https://github.com/anshenglv/ESurfingClient-CVersion-Android-APK)（免 Root 用户的首选 Android 客户端，感谢其开源分享与思路借鉴）
- **底层网络通信库**：[libcurl](https://curl.se/)
- **嵌入式 Web 服务器**：[Cesanta Mongoose](https://cesanta.com/)
- **UI 框架与跨语言互操作**：[Flutter Framework](https://flutter.dev/) & [Dart:FFI](https://dart.dev/guides/libraries/c-interop)

---

## 📄 License

本项目基于 [Apache License 2.0](LICENSE) 许可证开源。仅供计算机网络协议学习与技术交流使用，请勿用于违反校园网使用规范或商业用途。
