#!/system/bin/sh
# ESurfing Daemon — Magisk/KernelSU service.sh
# Runs in background after boot completes

MODDIR=${0%/*}
DATA_DIR=/data/adb/esurfing
DISABLE_FLAG="$DATA_DIR/disable"

# Wait for network to be ready
sleep 15

# Ensure data directory exists
mkdir -p "$DATA_DIR/portal"
mkdir -p "$DATA_DIR/webroot"

# Copy daemon binary (on module update the old binary is replaced)
cp "$MODDIR/esurfingd" "$DATA_DIR/esurfingd"
chmod 755 "$DATA_DIR/esurfingd"

# Copy portal files (always, to pick up updates)
cp -r "$MODDIR/portal/"* "$DATA_DIR/portal/" 2>/dev/null || true
chmod 644 "$DATA_DIR/portal/"* 2>/dev/null || true

# Copy KernelSU WebUI files
cp -r "$MODDIR/webroot/"* "$DATA_DIR/webroot/" 2>/dev/null || true
chmod 644 "$DATA_DIR/webroot/"* 2>/dev/null || true

# Copy default config if not present
if [ ! -f "$DATA_DIR/ESurfingClient.json" ]; then
  cp "$MODDIR/ESurfingClient.json" "$DATA_DIR/" 2>/dev/null || true
fi

# Create log symlink for web UI
ln -sf "$DATA_DIR/run.log" "$DATA_DIR/portal/run.log" 2>/dev/null || true
ln -sf "$DATA_DIR/run.log" "$DATA_DIR/webroot/run.log" 2>/dev/null || true

# Manual disable (KernelSU action / Web 停止服务) — skip auto-start without reboot
if [ -f "$DISABLE_FLAG" ]; then
  echo "esurfingd disabled by $DISABLE_FLAG, skip start" >> "$DATA_DIR/run.log" 2>/dev/null || true
  exit 0
fi

# Start the daemon
# Note: work() handles logger init, web server, config load, and thread supervisor.
# On crash, Magisk service.sh will NOT auto-restart (oneshot).
# Use a watchdog wrapper if auto-restart is desired.
exec "$DATA_DIR/esurfingd"
