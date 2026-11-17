#!/system/bin/sh
# ESurfing Daemon — Magisk/KernelSU service.sh
# Runs in background after boot completes

MODDIR=${0%/*}
DATA_DIR=/data/adb/esurfing
DISABLE_FLAG="$DATA_DIR/disable"

# Wait for network to be ready
sleep 15

# Ensure data directories exist with traversal permissions
mkdir -p "$DATA_DIR/portal" "$DATA_DIR/webroot"
chmod 755 "$DATA_DIR" "$DATA_DIR/portal" "$DATA_DIR/webroot" 2>/dev/null || true

# Clean up any leftover temporary config files from unexpected power loss
rm -f "$DATA_DIR"/ESurfingClient.json.*.tmp 2>/dev/null || true

# Copy daemon binary atomically (avoids ETXTBSY if previous binary inode is busy)
if cp -f "$MODDIR/esurfingd" "$DATA_DIR/esurfingd.new" 2>/dev/null; then
  chmod 755 "$DATA_DIR/esurfingd.new"
  mv -f "$DATA_DIR/esurfingd.new" "$DATA_DIR/esurfingd"
else
  cp -f "$MODDIR/esurfingd" "$DATA_DIR/esurfingd"
  chmod 755 "$DATA_DIR/esurfingd"
fi

# Sync portal and KernelSU WebUI files recursively
cp -rf "$MODDIR/portal/." "$DATA_DIR/portal/" 2>/dev/null || cp -r "$MODDIR/portal/"* "$DATA_DIR/portal/" 2>/dev/null || true
cp -rf "$MODDIR/webroot/." "$DATA_DIR/webroot/" 2>/dev/null || cp -r "$MODDIR/webroot/"* "$DATA_DIR/webroot/" 2>/dev/null || true

# Directories must keep 755 (+x traversal bit); regular files get 644
find "$DATA_DIR/portal" "$DATA_DIR/webroot" -type d -exec chmod 755 {} \; 2>/dev/null || true
find "$DATA_DIR/portal" "$DATA_DIR/webroot" -type f -exec chmod 644 {} \; 2>/dev/null || true

# Copy default config if not present
if [ ! -f "$DATA_DIR/ESurfingClient.json" ]; then
  cp "$MODDIR/ESurfingClient.json" "$DATA_DIR/" 2>/dev/null || true
  chmod 644 "$DATA_DIR/ESurfingClient.json" 2>/dev/null || true
fi

# Create log symlinks for Web UI
ln -sf "$DATA_DIR/run.log" "$DATA_DIR/portal/run.log" 2>/dev/null || true
ln -sf "$DATA_DIR/run.log" "$DATA_DIR/webroot/run.log" 2>/dev/null || true

# Manual disable (KernelSU action / Web 停止服务) — skip auto-start without reboot
if [ -f "$DISABLE_FLAG" ]; then
  echo esurfing_daemon > /sys/power/wake_unlock 2>/dev/null || true
  echo "esurfingd disabled by $DISABLE_FLAG, skip start" >> "$DATA_DIR/run.log" 2>/dev/null || true
  exit 0
fi

# Start the daemon
# Note: esurfingd internally manages /data/adb/esurfing/run.log, wake_lock, and child processes.
cd "$DATA_DIR" || exit 1
echo esurfing_daemon > /sys/power/wake_lock 2>/dev/null || true
exec "$DATA_DIR/esurfingd" </dev/null >/dev/null 2>&1
