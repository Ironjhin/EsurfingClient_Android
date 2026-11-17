#!/system/bin/sh
# ESurfing Daemon — KernelSU / Magisk action.sh
# Toggle daemon start/stop without rebooting the phone.
# KernelSU Manager shows an "Action" button for modules that ship this file.

MODDIR=${0%/*}
DATA_DIR=/data/adb/esurfing
BIN="$DATA_DIR/esurfingd"
PID_FILE="$DATA_DIR/esurfingd.pid"
DISABLE_FLAG="$DATA_DIR/disable"
LOG="$DATA_DIR/run.log"

log() {
  echo "[action] $1"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [action] $1" >> "$LOG" 2>/dev/null || true
}

sleep_step() {
  sleep 0.2 2>/dev/null || sleep 1
}

# Strictly verify a PID belongs to esurfingd via /proc/<pid>/cmdline or comm
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

is_running() {
  # Prefer validated PID file, fall back to process name
  if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE" 2>/dev/null)
    if is_esurfing_pid "$pid"; then
      return 0
    fi
  fi
  pidof esurfingd >/dev/null 2>&1 && return 0
  return 1
}

ensure_files() {
  mkdir -p "$DATA_DIR/portal" "$DATA_DIR/webroot"
  chmod 755 "$DATA_DIR" "$DATA_DIR/portal" "$DATA_DIR/webroot" 2>/dev/null || true

  if [ -f "$MODDIR/esurfingd" ]; then
    if [ ! -x "$BIN" ] || ! cmp -s "$MODDIR/esurfingd" "$BIN" 2>/dev/null; then
      if cp -f "$MODDIR/esurfingd" "${BIN}.new" 2>/dev/null; then
        chmod 755 "${BIN}.new"
        mv -f "${BIN}.new" "$BIN"
      else
        cp -f "$MODDIR/esurfingd" "$BIN"
        chmod 755 "$BIN"
      fi
    fi
  elif [ ! -x "$BIN" ]; then
    log "ERROR: daemon binary not found at $BIN"
    echo "错误: 找不到守护进程二进制"
    exit 1
  fi

  # Keep portal/webroot in sync and fix directory/file permissions
  cp -rf "$MODDIR/portal/." "$DATA_DIR/portal/" 2>/dev/null || cp -r "$MODDIR/portal/"* "$DATA_DIR/portal/" 2>/dev/null || true
  cp -rf "$MODDIR/webroot/." "$DATA_DIR/webroot/" 2>/dev/null || cp -r "$MODDIR/webroot/"* "$DATA_DIR/webroot/" 2>/dev/null || true
  find "$DATA_DIR/portal" "$DATA_DIR/webroot" -type d -exec chmod 755 {} \; 2>/dev/null || true
  find "$DATA_DIR/portal" "$DATA_DIR/webroot" -type f -exec chmod 644 {} \; 2>/dev/null || true

  if [ ! -f "$DATA_DIR/ESurfingClient.json" ] && [ -f "$MODDIR/ESurfingClient.json" ]; then
    cp "$MODDIR/ESurfingClient.json" "$DATA_DIR/"
    chmod 644 "$DATA_DIR/ESurfingClient.json" 2>/dev/null || true
  fi

  ln -sf "$LOG" "$DATA_DIR/portal/run.log" 2>/dev/null || true
  ln -sf "$LOG" "$DATA_DIR/webroot/run.log" 2>/dev/null || true
}

stop_daemon() {
  log "Stopping esurfingd..."
  touch "$DISABLE_FLAG"

  # Prefer graceful stop via HTTP API (triggers clean logout & supervisor shutdown)
  if is_running && command -v curl >/dev/null 2>&1; then
    curl -sS -m 3 -X POST "http://127.0.0.1:8888/api/stop" >/dev/null 2>&1 || true
    i=0
    while [ $i -lt 15 ]; do
      is_running || break
      sleep_step
      i=$((i + 1))
    done
  fi

  # Fallback: SIGTERM to verified supervisor / children and allow graceful logout
  if is_running; then
    if [ -f "$PID_FILE" ]; then
      pid=$(cat "$PID_FILE" 2>/dev/null)
      if is_esurfing_pid "$pid"; then
        kill -TERM "$pid" 2>/dev/null || true
      fi
    fi
    killall -TERM esurfingd 2>/dev/null || killall esurfingd 2>/dev/null || true
    i=0
    while [ $i -lt 12 ]; do
      is_running || break
      sleep_step
      i=$((i + 1))
    done
  fi

  # Last resort: SIGKILL any stuck orphan process
  if is_running; then
    killall -9 esurfingd 2>/dev/null || pkill -9 -f "$BIN" 2>/dev/null || true
    sleep 0.3 2>/dev/null || sleep 1
  fi

  rm -f "$PID_FILE"
  if is_running; then
    log "Failed to stop esurfingd"
    echo "停止失败：进程仍在运行"
    exit 1
  fi

  # Release kernel wake_lock so device can enter deep sleep
  echo esurfing_daemon > /sys/power/wake_unlock 2>/dev/null || true

  log "esurfingd stopped (disable flag set, wake_lock released)"
  echo "已停止守护进程（无需重启手机）"
  echo "下次开机也不会自动启动，直到再次执行 Action 启动"
}

start_daemon() {
  log "Starting esurfingd..."
  ensure_files
  rm -f "$DISABLE_FLAG"
  if is_running; then
    log "Already running"
    echo "守护进程已在运行"
    exit 0
  fi
  # Launch detached with /dev/null stdio:
  # esurfingd writes directly to run.log; redirecting stdout/stderr to run.log
  # would duplicate every line and hold rotated .rotate.log fds open forever.
  (
    cd "$DATA_DIR" || exit 1
    nohup "$BIN" </dev/null >/dev/null 2>&1 &
  )
  sleep 0.8 2>/dev/null || sleep 1
  if is_running; then
    log "esurfingd started"
    echo "已启动守护进程（无需重启手机）"
    echo "Web: http://127.0.0.1:8888/"
    exit 0
  fi
  # Some minimal environments lack nohup; retry with plain detached background
  (
    cd "$DATA_DIR" || exit 1
    "$BIN" </dev/null >/dev/null 2>&1 &
  )
  sleep 0.8 2>/dev/null || sleep 1
  if is_running; then
    log "esurfingd started (fallback)"
    echo "已启动守护进程（无需重启手机）"
    echo "Web: http://127.0.0.1:8888/"
    exit 0
  fi
  log "Failed to start esurfingd"
  echo "启动失败，请查看 $LOG"
  exit 1
}

# Main: toggle
if is_running; then
  stop_daemon
else
  start_daemon
fi
