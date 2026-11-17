#!/system/bin/sh
# ESurfing Daemon — customize.sh
# Runs during module installation (after Magisk/KernelSU extracts module files)

DATA_DIR=/data/adb/esurfing

# Ensure runtime directories exist with 755 traversal bits
mkdir -p "$DATA_DIR/portal" "$DATA_DIR/webroot"
chmod 755 "$DATA_DIR" "$DATA_DIR/portal" "$DATA_DIR/webroot" 2>/dev/null || true

# Preserve existing user configuration on upgrade; install template on fresh setup
if [ -f "$DATA_DIR/ESurfingClient.json" ]; then
  ui_print "- 保留已有配置文件: $DATA_DIR/ESurfingClient.json"
elif [ -n "${MODPATH:-}" ] && [ -f "$MODPATH/ESurfingClient.json" ]; then
  cp "$MODPATH/ESurfingClient.json" "$DATA_DIR/ESurfingClient.json" 2>/dev/null || true
  chmod 644 "$DATA_DIR/ESurfingClient.json" 2>/dev/null || true
fi

# Sync updated Web frontends immediately on install/upgrade
if [ -n "${MODPATH:-}" ]; then
  cp -rf "$MODPATH/portal/." "$DATA_DIR/portal/" 2>/dev/null || true
  cp -rf "$MODPATH/webroot/." "$DATA_DIR/webroot/" 2>/dev/null || true
  find "$DATA_DIR/portal" "$DATA_DIR/webroot" -type d -exec chmod 755 {} \; 2>/dev/null || true
  find "$DATA_DIR/portal" "$DATA_DIR/webroot" -type f -exec chmod 644 {} \; 2>/dev/null || true

  if command -v set_perm >/dev/null 2>&1; then
    set_perm "$MODPATH/esurfingd" 0 0 0755 2>/dev/null || true
    set_perm "$MODPATH/service.sh" 0 0 0755 2>/dev/null || true
    set_perm "$MODPATH/action.sh" 0 0 0755 2>/dev/null || true
    set_perm "$MODPATH/uninstall.sh" 0 0 0755 2>/dev/null || true
  else
    chmod 755 "$MODPATH/esurfingd" "$MODPATH/service.sh" "$MODPATH/action.sh" "$MODPATH/uninstall.sh" 2>/dev/null || true
  fi
fi

ui_print "- 安装完成 (ESurfing Daemon v2.3.1-r5)"
ui_print "- Web 管理后台: http://127.0.0.1:8888/"
ui_print "- 日志文件: /data/adb/esurfing/run.log"
