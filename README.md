# 天翼校园网认证客户端 — Magisk 模块

氛围编程的产物，我是小白一枚

纯 C 守护进程的 Magisk 模块，认证核心与 Flutter 版完全一致，去掉 Flutter UI，内存占用 ~1-2MB。安装后桌面出现 **ESurfing** 图标，点进去就是管理页面。

------
本分支 `magisk` — Magisk 模块版本。
另有 **Flutter APK 版本** 在 [main 分支](https://github.com/Ironjhin/EsurfingClient_Android/tree/main)，带原生 UI 界面。

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

## 安装

### 从 Release 安装

1. 前往 [Releases](https://github.com/Ironjhin/EsurfingClient_Android/releases?q=magisk) 下载 `esurfing-daemon-arm64-v8a.zip`
2. Magisk Manager → 模块 → 从本地安装 → 选择 zip
3. 重启手机

重启后桌面会出现 **ESurfing** 应用图标，打开即可管理。

### 首次配置

打开桌面的 **ESurfing** 应用，或 Magisk Manager 里点击「打开」，在 Web 管理页面填好账号密码点击保存。

## 与原版的差异

| 方面 | 原版 CVersion | 本模块 |
|------|--------------|--------|
| 平台 | Windows/Linux x64 | Android arm64 Magisk 模块 |
| 部署 | 手动编译或下载可执行文件 | Magisk Manager 一键安装 |
| 管理 | 控制台命令行 | Web 管理后台 + 桌面 APK |
| 守护 | 需 systemd 或任务计划 | 开机自动启动，root 级守护 |
| 日志 | 终端输出 | 文件日志 + Web 页面实时查看 |
| DNS | 未处理校园网 DNS 不可达 | 域名重写 + 公网 IP 直连 |
| 探测 | 单一 204 探测 | 双探针 + 超时降级（连通判定） |
| 线程 | 退出需手动重启 | 自动守护重启 |
| 闪退恢复 | 无 | `service.sh` 启动后常驻 |

## 目录结构

```
/data/adb/esurfing/
├── esurfingd               # 守护进程可执行文件
├── ESurfingClient.json     # 配置文件
├── esurfingd.pid           # PID 文件
├── run.log                 # 运行日志
├── *.rotate.log            # 轮转归档
└── portal/
    ├── index.html          # Web 前端
    └── run.log -> ../run.log
```

## 常见问题

**Q: 怎么确认 daemon 在运行？**
```bash
su -c "ps -A | grep esurfingd"
```

**Q: 怎么重启 daemon？**
```bash
su -c "killall esurfingd && sleep 1 && /data/adb/esurfing/esurfingd &"
```

**Q: 卸载模块后会残留文件吗？**
A: 卸载脚本会清理 `/data/adb/esurfing/` 下所有数据。

## License

Apache-2.0
