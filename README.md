# 天翼校园网认证客户端 (Android & Magisk)

> [!NOTE]
> 💬 **问题反馈与交流**：安卓客户端有任何使用疑问或 Bug 反馈，欢迎直接联系开发者邮箱：[2292219067@qq.com](mailto:2292219067@qq.com)。  
> 开发者主力日常使用 Magisk/KernelSU 模块版本，每次代码提交均会将 **Flutter 原生版** 与 **Magisk 模块版** 同步构建并持续维护更新。

专为 Android 移动平台设计的高可用广东天翼校园网认证客户端。上层提供现代化 **Flutter 原生拟态界面**，底层核心由纯 C 语言高并发引擎驱动，具备超低内存占用、智能掉线重连与全天候后台保活能力。

同时提供 **Magisk / KernelSU 专属 Root 守护进程模块**，开机即连、无感常驻、自带 WebUI 控制台。

---

## 🌟 核心特性

- **⚡ 纯 C 驱动，极速低耗**：底层认证、心跳保活与加解密引擎基于纯 C 语言与 libcurl 静态构建，无庞大运行时依赖，模块守护进程仅占 **1~2 MB 内存**。
- **🔄 同步上游最新协议引擎 (v2.1.7-r4)**：
  - **全渠道加解密支持**：原生支持 Android、Linux (PC)、Windows、macOS 与 iOS 动态 ZSM（TEA + LZMA）密钥解包。
  - **单调时钟防混乱**：心跳与超时全面采用单调时钟（`CLOCK_MONOTONIC`），杜绝设备息屏休眠、系统时间调整或 NTP 校时引发的会话突变。
  - **配置尽力解析机制**：即使配置未激活或部分参数缺失，也会完整保留已填账号信息，彻底杜绝 Web 端保存时配置被空值覆盖清空。
  - **异常断电与会话持久化**：具备会话现场归档（`.logout`），进程遇异常强杀或断电后，下次开机自动执行补登出，防止网关残留“异地已登录”限制。
- **📱 灵活的双形态支持**：
  - **Flutter APK 版 (本分支 `main`)**：免 Root、现代化 Material You / Liquid Glass 拟态界面、支持多账号快速切换、运行时间秒级显示、实时日志分析导出、前台服务防杀保活。
  - **Magisk / KernelSU 模块版 (`magisk` 分支)**：Root 专属、开机无感静默认证、后台永久驻留、内置 WebUI 管理面板 (`http://127.0.0.1:8888`)、支持 KernelSU WebUI 与 Action 免重启启停。
- **🛡️ 透明代理完美共存**：
  - 模块守护进程开机自动获取 `AID_NET_ADMIN` (`GID 3005`) 权限，原生命中 `Surfing` / `Mihomo` / `Clash.Meta` / `sing-box` / `Box4Magisk` 的首条直连豁免规则，彻底防止 TPROXY 误劫持与死循环断流。
  - 自动申请内核 `wake_lock`，有效抵御系统深度 Doze 睡眠冻结心跳。

---

## 🆚 双形态对比与选择

| 维度 | Flutter APK 原生版 (`main`) | Magisk / KernelSU 守护进程版 (`magisk`) |
| :--- | :--- | :--- |
| **运行权限** | 普通用户应用（免 Root） | 系统 Root 守护进程 (`root:3005`) |
| **内存占用** | 约 40 ~ 70 MB（Flutter 运行时） | **约 1 ~ 2 MB**（纯 C 二进制 `esurfingd`） |
| **交互界面** | 原生 Flutter App（支持动态取色与拟态） | 内置轻量 WebUI + 桌面专用管理图标 |
| **保活能力** | 前台通知服务 + 无障碍服务辅助保活 | **Root 级永驻**，系统杀后台机制完全免疫 |
| **开机自启** | 依赖系统自启管理与广播唤醒 | **系统开机阶段挂载启动**，亮屏前已联网 |
| **适用人群** | 未解锁 Bootloader、免 Root 日常使用 | 已 Root 玩家、需要极致省电与无感挂机体验 |

---

## 🚀 下载与安装

云端 CI 流水线对每次代码提交均提供全架构自动化打包编译：

### 1. Flutter APK 版 (免 Root)
1. 前往仓库的 [Releases 页面](https://github.com/Ironjhin/EsurfingClient_Android/releases)。
2. 找到带有 `v1.0.xx` 标签的最新 Release。
3. 下载附件中的 `app-release.apk`，在手机文件管理器中直接点击安装。

### 2. Magisk / KernelSU 模块版 (需 Root)
1. 前往仓库 [Releases 页面](https://github.com/Ironjhin/EsurfingClient_Android/releases?q=magisk)。
2. 下载 `esurfing-daemon-arm64-v8a.zip`。
3. 打开 **Magisk Manager** 或 **KernelSU Manager** $\to$ 「模块」 $\to$ 「从本地安装」选择该 zip 包。
4. 安装完成重启手机后：
   - 桌面会自动生成 **ESurfing** Web 控制端应用图标。
   - 也可直接在手机浏览器中访问 `http://127.0.0.1:8888/` 进行配置管理。
   - KernelSU 用户可在管理器模块卡片中直接点击 **WebUI** 按钮或 **Action** 按钮免重启启停服务。

---

## 🛠️ 底层引擎演进与核心修复 (v2.1.7-r4)

本项目底层 C 引擎持续跟进上游 [BadGhost520/ESurfingClient-CVersion](https://github.com/BadGhost520/ESurfingClient-CVersion) 的最新更新，并在移动端环境下做了深度优化与排坑：

| # | 问题 / 功能 | 诱因与现象 | 修复与改进实现 |
|---|---|---|---|
| **1** | **Windows 通道 ZSM 动态解密** | 上游 Windows 通道改用动态 TEA+LZMA 模块下发密钥 | 集成 `win_zsm` 模块动态解密解包算法，修正 `apply_channel_ua` 的 UA 传递 |
| **2** | **配置尽力解析防清空** | 配置文件在 `enabled: false` 时提前退出，导致内存账号为空，用户在 Web 端点保存直接冲掉原账号密码 | `load_cfg` 改为尽力解析模式：先填充内存再判定可用性，WebUI 无论何时都能读取磁盘真实现场 |
| **3** | **单调时钟防 Doze 混乱** | 息屏深度睡眠或连接 Wi-Fi 后 NTP 校时跳变，造成墙钟减法出现负数或超大数字，误触发心跳超时或一天重拨 | 全面改用 `get_steady_tm_ms()`（单调钟）测算心跳与会话寿命，彻底免疫系统时间调整 |
| **4** | **会话持久化与补登出** | 客户端被异常结束、断电重启后，网关依然记录该 MAC 在线，重连时返回异地登录错误 | 认证成功后自动将凭据持久化至 `.logout` 文件，下次启动时若探测到历史残留，优先补发 `term` 登出注销 |
| **5** | **息屏断流与 GID 豁免** | 息屏后系统冻结网络、或透明代理将网关探测与心跳流量误当成入站包劫持导致握手卡死 | 模块版自动申请 `wake_lock`，并赋予 `setgid(3005)`，无缝穿透 sing-box/Mihomo 透明代理直连出站 |
| **6** | **DNS 探针死锁与防污染** | 校园网在未认证时会劫持或污染 DNS，导致探测域名解析超时阻塞认证 | 采用多探针降级机制，支持公网 IP 直连与备用探针，探测超时智能判定网络连通状态 |
| **7** | **WebUI 状态与热重载** | Web 线程做耗时网络请求会锁死事件循环，且保存配置需要重启整个进程 | 状态接口读取内存缓存标志（非阻塞），应用配置支持平滑重载认证线程 |

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
     - 探测地址：`connect.rom.miui.com`、`1.1.1.1/32`、`220.181.104.183/32`
     - 认证与心跳服务器：`14.146.227.141/32`、`14.146.227.142/32`、`121.8.177.212/32`、`100.0.0.0/8`
     - 域名后缀：`+.cndatacom.com`、`+.cdcc.cn`、`+.189.cn`、`+.gd189.cn`、`+.edu.cn`

---

## 🔍 常见运行状态判定

打开 Flutter App 或 WebUI 后，日志面板会输出当前网络状态，可据此判断网关环境：

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
- **日志显示与思路借鉴**：[anshenglv/ESurfingClient-CVersion-Android-APK](https://github.com/anshenglv/ESurfingClient-CVersion-Android-APK)
- **底层网络通信库**：[libcurl](https://curl.se/)
- **嵌入式 Web 服务器**：[Cesanta Mongoose](https://cesanta.com/)
- **UI 框架与跨语言互操作**：[Flutter Framework](https://flutter.dev/) & [Dart:FFI](https://dart.dev/guides/libraries/c-interop)

---

## 📄 License

本项目基于 [Apache License 2.0](LICENSE) 许可证开源。仅供计算机网络协议学习与技术交流使用，请勿用于违反校园网使用规范或商业用途。
