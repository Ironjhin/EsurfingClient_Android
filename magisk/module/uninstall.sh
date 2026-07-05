#!/system/bin/sh
# ESurfing Daemon — uninstall.sh
# Cleanup all data on module removal

# Kill the daemon
kill $(cat /data/adb/esurfing/esurfingd.pid 2>/dev/null) 2>/dev/null || true

# Remove all data (config, logs, portal files)
rm -rf /data/adb/esurfing
