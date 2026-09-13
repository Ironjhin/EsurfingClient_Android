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

---

## 2. 网络代理冲突与 Box4Magisk 经验

### 连通性探测地址
客户端底层（`NetClient.c`）探测网络通畅与 Portal 拦截状态依赖以下目标：
1. **主检测**：`http://connect.rom.miui.com/generate_204`（期望 204 为正常联网，302 为需认证）
2. **备用检测**：`http://1.1.1.1`（期望 301 为正常联网，302 为需认证）
3. **认证服务器**：`http://14.146.227.141:7001`、`http://121.8.177.212:7001`
4. **心跳保活**：校园网内部网关 AC（通常为私有网段或校内 IP）

### Box4Magisk 共存规则
若同时启用 Box4Magisk（基于 iptables/nftables 的透明代理）：
- **Flutter APK 版**：在 `/data/adb/box/scripts/box.config` 的 `user_packages_list` 中排除包名 `com.example.esurfing_client`。
- **Magisk Daemon 版**：
  1. 在 `/data/adb/box/scripts/box.config` 的 `intranet` 中加入：
     `1.1.1.1/32`、`14.146.227.141/32`、`121.8.177.212/32` 及校内 Portal IP。
  2. 在 `/data/adb/box/sing-box.json` 的 `route.rules` 与 `dns.rules` 中将 `rom.miui.com` 与校园网域名设为 `direct` / `local` DNS。

---

## 3. 分支与工程规范
- **`main` 分支**：Flutter 客户端（Android APK），根目录与 `esurfing_flutter/` 目录源码需保持 1:1 同步。
- **`magisk` 分支**：Magisk / KernelSU root 模块守护进程源码（`magisk/` 目录）。
- **CI / CD**：推送至 `main` 自动构建 APK（`Flutter Universal APK Build`），推送至 `magisk` 自动构建模块 zip（`Build Magisk Module`）。
