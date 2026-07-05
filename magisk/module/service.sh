#!/system/bin/sh
# ESurfing Daemon — Magisk service.sh
# Runs in background after boot completes

MODDIR=${0%/*}

# Wait for network to be ready
sleep 15

# Ensure data directory exists
mkdir -p /data/adb/esurfing/portal

# Copy daemon binary (on module update the old binary is replaced)
cp "$MODDIR/esurfingd" /data/adb/esurfing/esurfingd
chmod 755 /data/adb/esurfing/esurfingd

# Copy portal files (always, to pick up updates)
cp -r $MODDIR/portal/* /data/adb/esurfing/portal/
chmod 644 /data/adb/esurfing/portal/* 2>/dev/null || true

# Copy default config if not present
if [ ! -f /data/adb/esurfing/ESurfingClient.json ]; then
  cp $MODDIR/ESurfingClient.json /data/adb/esurfing/ 2>/dev/null || true
fi

# Create log symlink for web UI
ln -sf /data/adb/esurfing/run.log /data/adb/esurfing/portal/run.log 2>/dev/null || true

# Start the daemon
# Note: work() handles logger init, web server, config load, and thread supervisor.
# On crash, Magisk service.sh will NOT auto-restart (oneshot).
# Use a watchdog wrapper if auto-restart is desired.
exec /data/adb/esurfing/esurfingd
