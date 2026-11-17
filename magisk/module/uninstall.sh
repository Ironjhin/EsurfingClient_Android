#!/system/bin/sh
# ESurfing Daemon — uninstall.sh
# Gracefully stop daemon (allowing campus logout), release wake_lock, and clean up data

DATA_DIR=/data/adb/esurfing
PID_FILE="$DATA_DIR/esurfingd.pid"

# Strictly verify a PID belongs to esurfingd (prevents killing reused system PIDs in post-fs-data)
is_esurfing_pid() {
  _pid="$1"
  case "$_pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ -d "/proc/$_pid" ] || return 1
  if [ -r "/proc/$_pid/cmdline" ]; then
    tr '\0' ' ' < "/proc/$_pid/cmdline" 2>/dev/null | grep -q "esurfingd" && return 0
  fi
  if [ -r "/proc/$_pid/comm" ]; then
    grep -q "esurfingd" "/proc/$_pid/comm" 2>/dev/null && return 0
  fi
  return 1
}

is_daemon_running() {
  if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE" 2>/dev/null)
    if is_esurfing_pid "$pid"; then
      return 0
    fi
  fi
  pidof esurfingd >/dev/null 2>&1 && return 0
  return 1
}

# 1. Request graceful stop via HTTP API or SIGTERM so auth child can logout cleanly
if is_daemon_running; then
  if command -v curl >/dev/null 2>&1; then
    curl -sS -m 2 -X POST "http://127.0.0.1:8888/api/stop" >/dev/null 2>&1 || true
  fi

  sent_term=0
  if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE" 2>/dev/null)
    if is_esurfing_pid "$pid"; then
      kill -TERM "$pid" 2>/dev/null || true
      sent_term=1
    fi
  fi
  if [ "$sent_term" -eq 0 ]; then
    killall -TERM esurfingd 2>/dev/null || killall esurfingd 2>/dev/null || true
  fi

  # Wait up to ~2.5-3s for graceful term() logout and child exit
  i=0
  while [ $i -lt 10 ]; do
    is_daemon_running || break
    if sleep 0.25 2>/dev/null; then
      i=$((i + 1))
    else
      sleep 1
      i=$((i + 4))
    fi
  done
fi

# 2. Fallback: terminate any remaining supervisor/child processes
if is_daemon_running; then
  killall esurfingd 2>/dev/null || pkill -f "$DATA_DIR/esurfingd" 2>/dev/null || true
  sleep 0.3 2>/dev/null || sleep 1
fi
if is_daemon_running; then
  killall -9 esurfingd 2>/dev/null || pkill -9 -f "$DATA_DIR/esurfingd" 2>/dev/null || true
  sleep 0.2 2>/dev/null || true
fi

# 3. Release kernel wake_lock to prevent battery drain after module removal
echo esurfing_daemon > /sys/power/wake_unlock 2>/dev/null || true

# 4. Remove all runtime data (config, logs, lock/pid, portal/webroot files)
rm -rf "$DATA_DIR"
