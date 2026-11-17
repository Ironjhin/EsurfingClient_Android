# ESurfing Daemon — Magisk / KernelSU / APatch Module

广东天翼校园网认证守护进程的 Root 模块版本（当前版本 **`v1.1.73` / Core `v2.3.1-r5`**）。纯 C 守护进程后台运行，内存占用 ~1–2 MB。

安装后桌面出现 **ESurfing** 图标，点进去即可进入 Web 管理后台；KernelSU / APatch 管理器中也有「WebUI」按钮直通新版离线控制台。

> **免 Root 安卓设备用户**：本项目仅专注维护 Magisk / KernelSU / APatch 模块版；免 Root 原生 Android APK 请前往安生同学开源项目下载：👉 **[anshenglv/ESurfingClient-CVersion-Android-APK](https://github.com/anshenglv/ESurfingClient-CVersion-Android-APK)**

## 系统要求

- 已 Root 的 Android 设备，装有 **Magisk 24.0+**、**KernelSU** 或 **APatch**
- 架构：**arm64-v8a**（仅此一档）

## 安装

### 从 Release 安装

1. 前往 [Releases](https://github.com/Ironjhin/EsurfingClient_Android/releases) 下载 `esurfing-daemon-arm64-v8a.zip`
2. Magisk Manager → 模块 → 从本地安装 → 选择 zip
3. 重启手机

重启后桌面会出现 **ESurfing** 应用图标，打开即可管理。

### 首次配置

**方法一：桌面的 ESurfing 应用**
打开即可看到管理页面，填好账号密码点击保存。

**方法二：Magisk Manager**
模块列表 → ESurfing Daemon → 底部「打开」按钮。

**方法三：直接编辑配置文件（需要 root）**

```bash
su -c "vi /data/adb/esurfing/ESurfingClient.json"
```

配置格式（模块默认 `ESurfingClient.json` 示例，完整参数可在 WebUI 保存后自动补全）：

```json
{
  "enabled": true,
  "log_lv": 4,
  "log_max_files": 5,
  "log_max_days": 3,
  "accounts": [
    {
      "username": "你的校园网账号",
      "password": "你的校园网密码",
      "channel": "android",
      "mark": "",
      "time_windows": []
    }
  ]
}
```

| 字段 | 说明 |
|------|------|
| `enabled` | 是否启用自动认证 |
| `log_lv` | 日志等级：`0=NONE`, `1=FATAL`, `2=ERROR`, `3=WARN`, `4=INFO` (默认), `5=DEBUG`, `6=TRACE` |
| `log_max_files` | 最多保留的历史归档日志份数（默认 `5`，范围 `0..100`，`0` 表示仅保留当前 `run.log`） |
| `log_max_days` | 历史归档日志保留天数（默认 `3`，范围 `0..365`，`0` 表示不限天数；总归档上限 `10 MB`） |
| `channel` | 认证通道：模块默认锁定 `android`（`3`，推荐）；另支持 `windows` / `linux` / `ios` / `macos` |
| `mark` | `SO_MARK` 路由标记（十六进制，多 WAN 环境用，留空自动分配；绑定失败自动放弃防串线） |
| `time_windows` | 分时段自动认证/下线时间窗列表 |
| `probe_hosts` | 自定义联网探测目标数组（支持最多 14 路固定 IPv4 并发探测，缺失时自动补全） |

## Web 管理

模块支持两种管理入口（均连接本地守护进程 `http://127.0.0.1:8888`）：

1. **KernelSU / APatch WebUI**（`webroot/index.html`）：全新响应式 Bento 卡片布局，100% 离线零外链（校园网未认证 `302` 状态秒开），支持深浅双主题切换、密码显隐、自定义弹窗、`probe_hosts` 折叠配置与着色过滤日志终端。
2. **桌面 WebView APK / 浏览器 Portal**（`http://127.0.0.1:8888/`）：桌面 **ESurfing** 应用（已启用 `usesCleartextTraffic="true"` 支持 Android 9+ 明文加载与返回键后退）或手机浏览器直接访问。

| 板块 | 说明 |
|------|------|
| 状态总览 | 显示认证状态（含异常/禁用/待配置提示）、网络连通状态与单调运行时长 |
| 配置表单 | 修改账号密码、通道、日志等级、归档保留策略 (`log_max_files`/`log_max_days`)、`mark`、超时及 `probe_hosts` |
| 保存并应用 | 无损合并保存配置并通过 `.apply` 标记平滑重载认证进程 |
| 服务控制 | 支持「强制重新认证」、基于 `bootId` 防竞态的「重启服务」以及「停止服务」 |
| 日志终端 | 实时查看、分级着色、筛选、复制、导出，并支持目录存储统计与模态确认一键清理 (`POST /api/logs/clear`) |

## 目录结构

```text
/data/adb/esurfing/
├── esurfingd                      # 守护进程可执行文件 (GID 3005 透明代理豁免)
├── ESurfingClient.json            # 配置文件
├── esurfingd.pid                  # 主守护进程 PID 文件
├── esurfingclient-*.lock          # 单实例文件锁 (main / web / auth-N)
├── run.log                        # 运行日志
├── *.rotate.log                   # 轮转归档（满 1000 行自动轮转，默认最多保留 5 份 / 3 天 / 总归档上限 10 MB）
├── portal/                        # 本地 Portal 静态资源 (http://127.0.0.1:8888/)
│   ├── index.html
│   └── assets/
└── webroot/
    └── index.html                 # KernelSU / APatch 离线 WebUI
```

`/system/app/ESurfingUI/` 内安装有 WebView 壳 APK，提供桌面内嵌管理界面。

## 日志

```bash
su -c "tail -f /data/adb/esurfing/run.log"
```

## 从源码构建

需要 Android NDK r27+、CMake 3.18+、Android SDK（编译 WebView APK 用）。

```bash
cd magisk

# 构建模块（同时编译 daemon 和 WebView APK）
export ANDROID_SDK_ROOT=/path/to/android-sdk
./build.sh

# 只打包不编译（已有二进制时）
./build.sh --module-only

# 产物
ls output/
# esurfing-daemon-arm64-v8a.zip
```

CI 自动构建在 GitHub Actions 的 `magisk` 分支上运行。

## 与原版 CVersion 的差异

这是基于 [BadGhost520/ESurfingClient-CVersion](https://github.com/BadGhost520/ESurfingClient-CVersion)（已同步至 **`v2.3.1-r5`**）的 Android Root 守护模块分支，主要增强：

| 方面 | 原版 CVersion (`v2.3.1-r5`) | 本模块 (`v1.1.73`) |
|------|--------------|--------|
| 平台 | Windows / Linux / OpenWrt | Android arm64 Magisk / KernelSU / APatch 模块 |
| 部署 | 手动编译或命令行部署 | 模块管理器一键刷入 + 桌面 WebView APK + KernelSU WebUI |
| 通道默认值 | 默认通道 `1` (`windows`) | Android 专属锁定默认通道 `3` (`android`)，规避高校 Windows 通道登录超时 |
| 单实例锁 | POSIX 锁路径位于 `/tmp` | 适配至 `/data/adb/esurfing/esurfingclient-*.lock` |
| 透明代理与保活 | 常规进程权限 | 自动切换 `GID 3005` (`AID_NET_ADMIN`) 免劫持 + 内核 `wake_lock`（停服/卸载自动释放） |
| 控制面板 | Portal (`http://127.0.0.1:8888`) | 同步新版 Portal + 全面重构的离线零外链 KernelSU Bento WebUI |

## 更新日志

完整更新日志见仓库根目录 **[CHANGELOG.md](../CHANGELOG.md)**。

### v1.1.73 (Core v2.3.1-r5)
- **多维自动日志轮转淘汰与安全清理**：新增 `log_max_files`（默认 `5`，`0..100`）、`log_max_days`（默认 `3`，`0..365`）与 `10 MB` 总归档兜底上限（`lstat` 精准过滤防误删、未同步 NTP 保护）；默认日志等级优化为 `INFO (4)`；新增 `POST /api/logs/clear` 支持原位 `truncate` 安全清空 `run.log`（保持多进程 `O_APPEND` 句柄不断裂）。
- **双端 WebUI 存储统计与清理**：KernelSU Bento WebUI 与 8888 原生 Portal 均接入日志存储占用实时统计、一键「清理日志」模态确认弹窗及 `log_max_files` / `log_max_days` 高级参数编辑。

### v1.1.72 (Core v2.3.1-r5)
- **同步上游 `v2.2.0-r5` → `v2.3.1-r5`**：连续两次 `302` 二次确认防误踢、60 秒内登录满 2 次暂停 35 分钟防风控锁、心跳区分网络/协议失败并按 `1/2/4/8/16/30s` 指数退避、最多 14 路固定 IPv4 `probe_hosts` 自定义并发探测、`main`/`web`/`auth-N` 单实例锁、`SO_MARK` 绑定失败丢弃防串线、`.apply` 热重载解耦、`States` (`cfg_t`) 重构及 `VERBOSE → TRACE` 更名。
- **KernelSU WebUI 全面重构**：响应式 Bento 卡片、深浅双主题自适应与切换、实时状态呼吸灯、密码显隐、自定义弹窗、`probe_hosts` 折叠面板及防 XSS 着色日志终端，100% 离线零外链。
- **模块稳定性与脚本修复**：修复 `Main.c` PID 误删与 `wake_lock` 泄漏、全链路切换 `CLOCK_MONOTONIC` 单调钟、修复 `SIGUSR1` 信号安全与 `WebLogFiles` 内存安全、修复禁用配置热重载死锁、`/api/restart` 端口冲突与 `GET /api/getConfigs` 首账号 `mark` 丢失；修复 `build.sh` / `service.sh` / `action.sh` / `uninstall.sh` 权限与日志双写问题，补齐 WebView APK `usesCleartextTraffic="true"`。

## 免重启启停（KernelSU / Magisk）

模块自带 `action.sh`。在 **KernelSU Manager → 模块 → ESurfing Daemon → Action**（部分 Magisk 也有「操作」按钮）可**无需重启手机**切换：

| 当前状态 | Action 效果 |
|---------|------------|
| 守护进程在跑 | 停止 `esurfingd`，并写入 `/data/adb/esurfing/disable`（下次开机也不再自动启动） |
| 守护进程已停 | 删除 `disable` 标记并立即后台启动守护进程 |

也可用 Web 后台的「⏹ 停止服务」（`POST /api/stop`）通知守护进程优雅登出退出——注意 Web 端停止**不会**写入 `disable` 标记（下次开机仍自动启动，当前会话也可直接点一次模块 Action 重新拉起）；只有通过模块 Action 停止才会写入 `/data/adb/esurfing/disable` 阻止开机自启。重新启动请点一次模块 Action，或：

```bash
su -c "rm -f /data/adb/esurfing/disable && /data/adb/esurfing/esurfingd &"
```

注意：这只是停掉本模块守护进程，**不是** KernelSU/Magisk 的「禁用模块」勾选（那个仍需重启才能卸载挂载点）。对本项目而言，停掉 daemon 已足够停止校园网认证。

## 常见问题

**Q: 切屏/息屏后会不会被杀？**
A: 不会。以 root 身份运行，不受 Android 省电策略和进程生命周期管理影响。

**Q: 怎么确认 daemon 在运行？**
```bash
su -c "ps -A | grep esurfingd"
```

**Q: 怎么重启 daemon？**
```bash
su -c "killall esurfingd && sleep 1 && /data/adb/esurfing/esurfingd"
```

**Q: 怎么不重启手机就关掉/打开？**
A: KernelSU 模块页点 **Action** 切换；或 Web 点「停止服务」后，再用 Action 启动。

**Q: 卸载 Magisk 模块后会不会残留文件？**
A: 卸载脚本会清理 `/data/adb/esurfing/` 下所有数据，包括日志和配置。

## License

Apache-2.0
