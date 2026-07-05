# ESurfing Daemon — Magisk Module

广东天翼校园网认证守护进程的 Magisk 模块版本。去掉 Flutter UI，纯 C 守护进程后台运行，内存占用 ~1-2MB。

## 系统要求

- 已 Root 的 Android 设备，装有 **Magisk 24.0+**
- 架构：arm64-v8a（推荐）、armeabi-v7a、x86_64

## 安装

### 从 Release 安装

1. 前往 [Releases](https://github.com/Ironjhin/EsurfingClient_Android/releases) 下载对应架构的 zip
2. Magisk Manager → 模块 → 从本地安装 → 选择 zip
3. 重启手机

### 首次配置

重启后 daemon 会自动启动。打开浏览器访问 `http://192.168.100.1:8888/`：

- 在 Web 管理页面填入校园网账号密码
- 点击 **保存并重启** 使配置生效

或者直接编辑配置文件（需要 root）：

```bash
su -c "vi /data/adb/esurfing/ESurfingClient.json"
su -c "killall esurfingd && /data/adb/esurfing/esurfingd"
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

浏览器打开 **[http://192.168.100.1:8888/](http://192.168.100.1:8888/)**

| 页面 | 说明 |
|------|------|
| 状态面板 | 显示认证状态和网络状态 |
| 配置表单 | 修改账号密码、日志等级、通道 |
| 保存并重启 | 保存配置后重启认证线程 |
| 日志查看 | 查看实时运行日志（需 symlink） |

## 日誌

```
/data/adb/esurfing/run.log         # 当前日志
/data/adb/esurfing/*.rotate.log    # 轮转归档（满 10000 行后自动轮转）
```

查看日志：

```bash
su -c "tail -f /data/adb/esurfing/run.log"
```

## 目录结构

```
/data/adb/esurfing/
├── esurfingd               # 守护进程可执行文件
├── ESurfingClient.json     # 配置文件
├── esurfingd.pid           # PID 文件
├── run.log                 # 运行日志
└── portal/                 # Web 前端文件
    ├── index.html
    └── run.log -> ../run.log  # 日志 symlink
```

## 从源码构建

需要 Android NDK r27+ 和 CMake 3.18+。

```bash
# 进入 magisk 目录
cd magisk

# 构建 arm64-v8a 模块
./build.sh

# 构建其他架构
./build.sh --abi armeabi-v7a
./build.sh --abi x86_64

# 只打包不编译（已有二进制时）
./build.sh --module-only

# 产物
ls output/
# esurfing-daemon-arm64-v8a.zip
```

CI 自动构建在 GitHub Actions 的 `magisk` 分支上运行。

## 常见问题

**Q: 切屏/息屏后会不会被杀？**
A: 不会。Magisk 模块以 root 身份运行，不受 Android 省电策略和进程生命周期管理影响。

**Q: 怎么确认 daemon 在运行？**
```bash
su -c "ps -A | grep esurfingd"
```

**Q: 怎么重启 daemon？**
```bash
su -c "killall esurfingd && sleep 1 && /data/adb/esurfing/esurfingd"
```

**Q: 卸载 Magisk 模块后会不会残留文件？**
A: 卸载脚本会清理 `/data/adb/esurfing/` 下所有数据。

## License

Apache-2.0
