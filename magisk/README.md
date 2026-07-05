# ESurfing Daemon — Magisk Module

广东天翼校园网认证守护进程的 Magisk 模块版本。去掉 Flutter UI，纯 C 守护进程后台运行，内存占用 ~1-2MB。

安装后桌面出现 **ESurfing** 图标，点进去就是管理页面。Magisk Manager 里也有「打开」按钮直通 Web UI。

## 系统要求

- 已 Root 的 Android 设备，装有 **Magisk 24.0+**
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

配置格式：

```json
{
  "enabled": true,
  "log_lv": 5,
  "accounts": [
    {
      "username": "你的校园网账号",
      "password": "你的校园网密码",
      "channel": "phone",
      "mark": ""
    }
  ]
}
```

| 字段 | 说明 |
|------|------|
| `enabled` | 是否启用自动认证 |
| `log_lv` | 日志等级：2=ERROR, 3=WARN, 4=INFO, 5=DEBUG, 6=VERBOSE |
| `channel` | `phone` 手机端 UA / `pc` 电脑端 UA |
| `mark` | SO_MARK 路由标记（十六进制，多 WAN 环境用，留空自动分配） |

## Web 管理

模块自带的 WebView APK 打开 `http://127.0.0.1:8888/`：

| 页面 | 说明 |
|------|------|
| 状态面板 | 显示认证状态和网络状态 |
| 配置表单 | 修改账号密码、日志等级、通道 |
| 保存并重启 | 保存配置后重启认证线程 |
| 日志查看 | 查看实时运行日志 |

## 目录结构

```
/data/adb/esurfing/
├── esurfingd               # 守护进程可执行文件
├── ESurfingClient.json     # 配置文件
├── esurfingd.pid           # PID 文件
├── run.log                 # 运行日志
├── *.rotate.log            # 轮转归档（满 10000 行后自动轮转）
└── portal/
    ├── index.html          # Web 前端
    └── run.log -> ../run.log
```

/system/app/ESurfingUI/ 内安装有 WebView 壳 APK，提供内嵌管理界面。

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

这是基于 [BadGhost/ESurfingClient-CVersion](https://github.com/BadGhost520/ESurfingClient-CVersion) 的深度改造分支，主要改进：

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

**Q: 卸载 Magisk 模块后会不会残留文件？**
A: 卸载脚本会清理 `/data/adb/esurfing/` 下所有数据，包括日志和配置。

## License

Apache-2.0
