# Changelog

本项目专注于 **Magisk / KernelSU / APatch Root 守护进程模块**（`esurfingd`）的维护与深度优化。  
免 Root 原生 Android 客户端请前往安生同学维护的开源项目：**[anshenglv/ESurfingClient-CVersion-Android-APK](https://github.com/anshenglv/ESurfingClient-CVersion-Android-APK)**。

---

## v1.1.72 (Core v2.3.1-r5)

### 一、同步上游核心 `v2.2.0-r5` → `v2.3.1-r5`

- **认证防风控保护 (`DialerClient.c`)**：
  - 连续两次检测到 `302` 重定向二次确认后才触发重新认证，防止网关瞬时抖动或探测超时误踢好会话。
  - 新增登录频率保护：60 秒内登录满 2 次仍被要求认证时自动暂停自动认证 35 分钟。
  - 常规认证失败退避表（`1 / 3 / 5 / 10 / 20 / 35` 分钟）尾档由 30 分钟调整为 35 分钟，避开服务端 30 分钟整点锁定窗口。
- **心跳保活增强 (`DialerClient.c`, `DialerNet.c`)**：
  - 区分网络不通 (`HB_NET_FAIL`) 与服务端拒绝 (`HB_PROTO_FAIL`)。
  - 心跳失败采用 `1 / 2 / 4 / 8 / 16 / 30s` 指数退避重试（总窗口约 61 秒，期间可被重启/退出/重认证请求即时打断）。
  - 纯网络波动耗尽重试后不再盲目退登，推迟至下个心跳周期再试；收到服务端 `FATAL` / `SLOW` 拒绝时立即触发重新认证。
- **自定义联网探测 (`probe_hosts`) (`CheckNetwork.c`, `Config.c`, `WebApiGet.c`)**：
  - 支持最多 14 路固定 IPv4 并发探测（`PROBE_MAX = 16`，其中两台认证服务器固定占 2 路，其余最多 14 路供自定义探测目标使用；最多支持 8 个探测域名、单域名最多 4 个固定 IPv4）。
  - 配置文件缺失 `probe_hosts` 时自动补全默认探测目标并原子写回配置文件；Portal 前端与 KernelSU WebUI 均支持可视化编辑。
- **多进程单实例锁与路由标记加固 (`DialerClient.c`, `DialerAuth.c`, `NetClientCurl.c`, `Config.c`)**：
  - 新增 `main` / `web` / `auth-N` 单实例文件锁（带 `O_CLOEXEC`），防止同账号多开互相踢下线。
  - `work_auth` 主线程显式绑定 `tl_thread_idx = 0`；`open_socket_callback` 绑定 `SO_MARK` 失败时直接 `close` socket 并返回 `CURL_SOCKET_BAD` 放弃当次请求，防止多线环境串线。
  - 增强非字符串 `mark` 字段容错处理，并在全平台内存配置解析中保持行为一致。
- **配置生命周期与内核重构 (`States.h`, `States.c`, `Config.c`, `SupervisorLoop.c`, `Logger.h`, `WebApiPost.c`)**：
  - 配置保存与应用解耦：引入基于 `.apply` 标记的平滑热重载机制（`cfg_request_apply` / `cfg_take_apply_request`）。
  - 全局运行状态统一收拢至 `States`（`login_cfg_t` 重构为 `cfg_t`，移除已废弃的 `SupervisorState.c`）。
  - 日志等级 `VERBOSE`（等级 `6`）全仓更名为 `TRACE`。

### 二、Magisk / KernelSU 模块专属升级与全量 Bug 修复

- **KernelSU WebUI 全面现代化重构 (`magisk/module/webroot/index.html`)**：
  - 采用全新响应式 Bento 卡片布局与移动端触控优化，支持深浅双主题跟随系统自适应及顶部一键切换。
  - 顶栏集成版本徽章与实时状态呼吸指示灯；状态卡片展示认证状态、网络连通、单调运行时长及异常/禁用/待配置提示横幅。
  - 新增密码显隐开关、滑动开关、自定义模态确认弹窗，以及可折叠的「高级参数与探测目标 (`probe_hosts`)」面板。
  - 重构现代日志终端：支持按等级语法着色渲染（渲染前严格 HTML 转义防 XSS）、级别筛选与关键字过滤、自动滚动开关、一键复制与导出 `esurfing-run.log`。
  - 100% 单文件离线零外链，确保校园网未认证 `302` 拦截断网状态下秒开；完整保留 `http://127.0.0.1:8888` 接口、`cachedConfig` 无损合并保存、校验阻断及 `bootId` 重启防竞态。
- **Android / 高校校园网防坑适配**：
  - Android / Magisk 默认锁定通道 `3` (`android`)，Portal 与 KernelSU WebUI 默认/缺省通道保持 `'android'`，规避五邑大学等高校使用 Windows 通道时登录 POST `CURLcode: 28` 超时问题。
  - `__MAGISK__` 环境下单实例锁路径适配至 `/data/adb/esurfing/esurfingclient-%s.lock`，解决 Android 无 `/tmp` 目录导致锁失效的问题。
  - 保持启动自动切换 `GID 3005` (`AID_NET_ADMIN`)，无缝命中透明代理直连豁免规则。
- **守护稳定性、内存与打包脚本全量修复**：
  - **PID 与 WakeLock 生命周期修复 (`Main.c`, `SimProcess.c`)**：仅在非查询模式且主守护进程抢到 `main` 单实例锁后才写 `esurfingd.pid`、注册退出清理并持有 `wake_lock` (`esurfing_daemon`)；修复查询命令或重复启动误删运行中 PID 文件、停止服务后 `wake_lock` 未释放导致无法深度休眠的问题；后台重定向时自动禁用控制台重复输出。
  - **单调时钟 (`CLOCK_MONOTONIC`) 全链路合规 (`SupervisorChild.c`, `SupervisorLoop.c`, `NetTraffic.c`, `HotspotControl.c`, `WebApiGet.c`)**：子进程重启退避、`/api/status/uptime`、网速采样及热点节流全面切换 `get_steady_tm_ms()` 并带无符号下溢保护，消除手机开机联网 NTP 校时跳变导致的卡死与计时错乱。
  - **信号原子安全修复 (`SupervisorSignal.c`, `States.h`)**：`g_need_restart` / `g_supervisor_stop` / `g_stop_requested` 统一改为 `volatile sig_atomic_t`，消除 `SIGUSR1` 信号处理未定义行为。
  - **Web 后端与配置核心加固 (`WebApiGet.c`, `WebApiPost.c`, `WebLogFiles.c`, `WebServer.c`, `Config.c`, `LoggerDir.c`)**：修复 `WebLogFiles` 栈缓冲越界与未补 `\0` 脏字符拼接及泄漏；修复禁用配置后 `POST /api/applyConfigs` 返回 `503` 导致无法重新拉起认证的死锁；修复 `/api/stop` 与 `/api/restart` 在不同角色下的误杀父进程、8888 端口争抢与 `bootId` 检测；修复 `GET /api/getConfigs` 丢失首账号 `mark` 与多账号顺序错乱、坏配置提前返回缺失默认 `probe_hosts` 的问题；补齐 `sim_thread_destroy` 释放、空配置 fd 泄漏、空子目录双斜杠路径与可中断等待修复。
  - **模块脚本、WebView APK 与 CI 修复 (`magisk/build.sh`, `service.sh`, `action.sh`, `customize.sh`, `uninstall.sh`, `magisk/app/`, `.github/workflows/build-magisk-module.yml`)**：修复 `build.sh` 漏拷贝 `portal/assets/` 静态资源；修复 `service.sh` 剥夺子目录 `+x` 权限的问题；修复 `action.sh` 双写 `run.log`、补充 PID 归属校验与停用释放 `wake_unlock`；修复 `uninstall.sh` 未等待优雅登出且未校验 PID 归属即强杀、残留 `wake_lock` 的问题；为桌面 WebView APK 补充 `android:usesCleartextTraffic="true"` 与返回键导航；新增 `.gitattributes` 锁定 `.sh` 与 `module.prop` 为 LF 换行符。

---

## v1.1.71 (Core v2.2.0-r5)

- 同步上游 `v2.2.0-r5` 核心更新（心跳日志降级、探测 `mark` 绑定、非认证线程越界防御）。
- 完善 CI 构建忽略 Markdown 变更与桌面文档引导，全面收敛至 Magisk / KernelSU 守护进程模块并导流免 Root 用户至安生同学 APK 项目。
