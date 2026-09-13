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

### PowerShell 文件输出编码禁忌（重要）
- **严禁在 PowerShell 中使用 `>` 重定向写入将被推送至 Android / Linux 的文本文件**！PowerShell 5.1 的 `>` 默认输出为 `UTF-16 LE` 编码，会导致 Android WebView 将中文渲染为乱码且 JavaScript 语法解析崩溃。
- 生成推送到设备的配置文件或 HTML 时，必须使用 Python 二进制模式写入、`[System.IO.File]::WriteAllBytes`，或显式指定 `-Encoding utf8`。

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
     - 在 `/data/adb/singbox/scripts/constants.sh` 的 `INTRANET_V4` 中加入：`100.0.0.0/8`（覆盖高校 Wi-Fi 常见的 `100.2.x.x` 内部网段）、`1.1.1.1/32`、`14.146.227.141/32`、`121.8.177.212/32`。
     - 在 `iptables.sh` 中，`bypass_intranet` 规则必须置于 `handle_packages`（应用过滤）之前，且需同时加入 `-s "${subnet}"` 和 `-d "${subnet}"` 的双向 RETURN 规则。
  3. 在 `config.json` 的 `route.rules` 与 `dns.rules` 中将 `rom.miui.com` 与 `edu.cn` 设为 `direct` / `local` DNS。

---

## 4. 守护进程状态机与控制规范
- **待机就绪状态同步**：主循环在 `STATUS_OK`（已联网就绪）循环探测时，必须持续设置 `is_connected = true`，避免 WebUI 与外部接口返回假离线。
- **控制信号中断响应**：任何长休眠或主循环等待分支必须同步轮询并响应 `is_need_reset`、`g_need_stop_now` 和 `g_need_restart_now`，确保网页端重置、停止与重启随时可用。

---

## 5. 分支与工程规范
- **`main` 分支**：Flutter 客户端（Android APK），根目录与 `esurfing_flutter/` 目录源码需保持 1:1 同步。
- **`magisk` 分支**：Magisk / KernelSU root 模块守护进程源码（`magisk/` 目录）。
- **CI / CD**：推送至 `main` 自动构建 APK（`Flutter Universal APK Build`），推送至 `magisk` 自动构建模块 zip（`Build Magisk Module`）。
