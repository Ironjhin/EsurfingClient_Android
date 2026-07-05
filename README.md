# 天翼校园网认证客户端 (Android)

氛围编程的产物，我是小白一枚

这是一个专为 Android 平台设计的校园网极速认证客户端。界面使用 Flutter 开发，核心拨号与协议控制由底层 C 语言引擎驱动，具备极低的内存占用与高效的后台保持能力。

------
本分支 `main` — Flutter APK 版本。
另有 **Magisk 模块版** 在 [magisk 分支](https://github.com/Ironjhin/EsurfingClient_Android/tree/magisk)，纯 C daemon ~1-2MB，开机自启，提供 Web 管理面板。

## 🤝 开源引用与致谢

本项目的顺利实现离不开开源社区的贡献，核心协议逻辑、加密算法及技术架构主要借鉴与引用了以下项目：

### 1. 核心协议与算法来源
* **天翼认证核心算法**：[BadGhost520](https://github.com/BadGhost520/ESurfingClient-CVersion) —— 提供了天翼校园网私有协议的加解密核心、XML 报文组包逻辑以及核心控制流的基础参考。
* 还有另外一位佬给的日志显示的思路 [anshenglv](https://github.com/anshenglv/ESurfingClient-CVersion-Android-APK)

### 2. 底层依赖与工具链
* **网络传输引擎**：基于 [libcurl](https://curl.se/) 静态库实现 —— 负责底层纯净套接字（Socket）的生命周期管理、多线程网络请求以及高效的 Captive Portal（302/204）拦截状态探测。
* **应用开发框架**：基于 [Flutter Framework](https://flutter.dev/) —— 驱动上层 UI 状态机的高效渲染、异步日志流的增量轮询以及跨平台架构的构建。
* **跨语言通信桥梁**：依托 Dart 原生 [Dart:FFI (Foreign Function Interface)](https://dart.dev/guides/libraries/c-interop) 机制 —— 实现了 Flutter 内存应用层与底层 C 语言编译期高并发线程（pthread）之间的低延迟双向数据穿透。

## 与原版 CVersion 的差异修复

本项目基于 [BadGhost/ESurfingClient-CVersion](https://github.com/BadGhost520/ESurfingClient-CVersion) 的 C 引擎，在此基础上做了大量修复和增强：

### 已修复的核心问题

| # | 问题 | 原因 | 修复 |
|---|------|------|------|
| 1 | 认证后 10 秒断网 | 主探测返回 curl 56（网关重置），备用探测 DNS 解析失败（curl 6），双失败 → 线程报错退出 → 发送 term 登出 | 备用探针改用不可路由 IP `192.0.2.1`，超时判定为已连接（与 PC 客户端一致） |
| 2 | `FOLLOWLOCATION` 掩盖重定向 | curl 跟随 302 后目标 DNS 解析失败，返回 curl 6，CODE 只看结果不知道之前有重定向 | 在检查 `curl_easy_perform` 返回值之前先查 `CURLINFO_REDIRECT_COUNT` |
| 3 | 线程死后无法重启 | 线程退出后 `pthread_t` 句柄仍非 NULL，`esurfing_client_start()` 直接返回 0 | 增加 `_is_thread_alive()` 检测线程真实存活状态，死线程先 join 再重建 |
| 4 | Portal 域名 DNS 不可达 | 校园网认证前无法解析内部 DNS（如 `enet.10000.gd.cn`） | 检测到 captive portal 重定向后，将已知 portal 域名替换为公网 IP `125.88.59.131` |
| 5 | 探测 URL 返回 502 不会用备用 | 单探针失败即判定为网络错误 | 统一 fallback 链：主探针非 302/非 204 → 自动尝试备用 |
| 6 | `esurfing_client_stop()` 来源不明 | Flutter 切屏触发 lifecycle 变化，间接调用 stop 导致断网 | 添加 `LOG_DEBUG` 追踪调用者、增加 30 秒「认证后护盾」防止误重置 |
| 7 | 设置页面「启用服务」不生效 | `enabled` 字段只用来显示状态文字，`_toggleAuth()` 从未被自动调用 | `_initApp()` 中检查 `enabled==true` 且有有效账号时自动调用开始认证 |
| 8 | 日志没有「已连接」提示 | `LOG_INFO("已连接至互联网")` 放在未认证分支中 | 移到 REQUEST_SUCCESS 全局分支，认证后无条件输出 |
| 9 | User-Agent 不匹配 | 移动端 UA 导致广东电信 portal 返回手机版页面，配置提取失败 | 恢复 PC 端 UA `CCTP/Linux64/1003` |
| 10 | NULL 解引用闪退 | Portal 配置 XML 结尾标签缺失时未做容错 | 增加结尾标签缺失保护 |
| 11 | 校园网标志 `readlink` 死循环 | `get_school_network_symbol()` 指针空悬 | 增加三层判空保护 |
| 12 | 备用探针无意义 fallback | AC IP（`wlanacip`）不 serve portal 页面 | 删除 AC fallback 逻辑 |

## 🚀 如何下载与安装

无需复杂的编译配置，云端自动化流水线已经为你打包好了开箱即用的原生安装包：

1. 进入当前 GitHub 仓库的 **Releases** 页面（位于仓库右侧栏）。
2. 选择最新版本（版本号格式形如 `v1.0.xx`）。
3. 在附件（Assets）中直接点击 `app-release.apk` 下载到手机。
4. **注意**：下载产物为原生安装包文件，无需解压，直接在手机文件管理器中点击即可覆盖升级或安装。

---

## 🛠️ 功能与操作指南

打开 App 后，你会看到一个简洁的控制面板，核心操作如下：

### 1. 账号配置
* 界面会显示当前配置的物理账号（如学号）及使用的拨号通道。
* 客户端支持多账号快速状态切换。

### 2. 状态控制按钮
* **【开始认证】**：点击后，程序将通过 FFI 管道激活后台独立的 C 语言认证线程。客户端会自动探测网络网关环境，并在遭遇网关拦截时自动执行私有协议握手。
* **【停止认证】**：点击后，彻底物理终止后台拨号线程，断开当前的认证状态守护。

### 3. 运行日志面板
* 面板会增量刷新当前的底层网络状态和系统行为。
* **【清空】按钮**：点击后将瞬间清空界面上的历史日志，同时底层 C 语言引擎会执行磁盘文件截断，确保物理日志体积立刻归零，不占用手机存储空间。
* **【导出】按钮**：将日志文件导出分享，方便调试。

---

## 🔍 常见运行状态判定（排查必备）

当你点击"开始认证"后，日志面板会打印不同的状态提示。请根据以下特征判定当前网络物理现状：

### 1. 日志频繁提示 `Status code: 204 ... Network might be already online`
* **因果关系**：这代表客户端发出的网络探测包直接送达了外网（未被学校网关拦截）。
* **可能原因**：
  * 你的手机当前同时开启了 **移动蜂窝数据（4G/5G）**，系统自动将探测流量路由到了数据流量通道，绕过了 Wi-Fi 网关。
  * 你的设备当前已经处于登录成功状态，或者网关仍缓存着你的物理 MAC 地址白名单。
* **恢复路径**：请彻底关闭手机的移动数据流量，仅保留 Wi-Fi 关联；或者在官方网页端执行下线注销，强迫网关重新进入拦截状态。

### 2. 日志显示 `[T-0] 认证线程 0 创建成功` 并在 10 秒后持续刷新
* **因果关系**：说明 Dart 界面层与底层 C 语言引擎的通信管道完全正常，系统正以 10 秒/次的低频心跳安全守护网络，严禁裸跑暴刷。

---

## 🤖 开发者自动化提交说明（针对项目维护）

本项目已完全闭环云端流水线。当需要更新代码并发布新版本时：

1. 本地代码修改完成后，直接在终端执行标准推送：
   ```shell
   git add .
   git commit -m "feat: 你的修改说明"
   git push origin main
   ```
2. GitHub Actions 自动监听 `main` 分支推送事件。
3. 云端将自动执行以下步骤：
   * 拉取最新源码 + NDK 预置工具链。
   * 通过 CMake + NDK 交叉编译 arm64-v8a / armeabi-v7a / x86_64 / x86 四套架构的 `libesurfing_client.so`。
   * 执行 `flutter build apk` 全架构通用包编译。
   * 使用 GitHub API 自动生成 `v1.0.run_number` 版本标签，发布 Release 并上传 APK。
4. 等待约 5-8 分钟流水线变绿后，打开本仓库的 Releases 页面即可下载尝鲜。

**注意事项**：
* 请确保未将编译产物（`build/`、`android/.gradle/`、`*.so` 等）提交到仓库，以免增加仓库体积。
* CI 配置文件位于 `.github/workflows/build-apk.yml`。
