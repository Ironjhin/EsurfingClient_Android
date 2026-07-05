#!/system/bin/sh
# ESurfing Daemon — customize.sh
# Runs during module installation (before/after file copy)

# Ensure data directory exists
mkdir -p /data/adb/esurfing/portal

# Preserve existing config and portal files on upgrade
if [ -f /data/adb/esurfing/ESurfingClient.json ]; then
  ui_print "保留已有配置文件"
fi
if [ -f /data/adb/esurfing/portal/index.html ]; then
  ui_print "保留已有 Web 前端文件"
fi

ui_print "安装完成"
ui_print "Web 管理后台: http://127.0.0.1:8888/"
ui_print "日志文件: /data/adb/esurfing/run.log"
