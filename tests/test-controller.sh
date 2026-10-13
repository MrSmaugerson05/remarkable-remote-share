#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CONTROLLER=$ROOT/src/controller/remote-share-control
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/remote-share-controller.XXXXXXXX")
FAKE_BIN=$TEST_ROOT/fake-bin
APP=$TEST_ROOT/app

cleanup() {
    if [ -x "$APP/remote-share-control" ]; then
        env "${COMMON_ENV[@]}" "$APP/remote-share-control" off >/dev/null 2>&1 || true
    fi
    case "$TEST_ROOT" in "${TMPDIR:-/tmp}"/remote-share-controller.*) rm -rf "$TEST_ROOT" ;; esac
}
trap cleanup EXIT

mkdir -p "$FAKE_BIN" "$APP/bin" "$APP/run" "$APP/state"
cp "$CONTROLLER" "$APP/remote-share-control"
chmod +x "$APP/remote-share-control"

cat > "$APP/bin/tailscaled" <<'PY'
#!/usr/bin/env python3
import os, signal, socket, sys, time
if os.environ.get("MOCK_MODE") == "daemon-failure":
    sys.exit(1)
sock_path = next(a.split("=", 1)[1] for a in sys.argv if a.startswith("--socket="))
try:
    os.unlink(sock_path)
except FileNotFoundError:
    pass
server = socket.socket(socket.AF_UNIX)
server.bind(sock_path)
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
while True:
    time.sleep(1)
PY
chmod +x "$APP/bin/tailscaled"

cat > "$APP/bin/tailscale" <<'SH'
#!/bin/sh
case "$1" in --socket=*) shift ;; esac
command=${1:-}
case "$command" in
    up)
        [ "${MOCK_MODE:-}" != auth-required ] || { echo 'authentication required' >&2; exit 1; }
        [ "${MOCK_MODE:-}" != tailscale-failure ] || exit 1
        ;;
    serve)
        [ "${2:-}" = reset ] && exit 0
        [ "${MOCK_MODE:-}" != serve-failure ] || exit 1
        ;;
    ip) echo '192.0.2.24' ;;
    status) echo 'connected' ;;
    set|down) ;;
    *) exit 2 ;;
esac
SH
chmod +x "$APP/bin/tailscale"

cat > "$FAKE_BIN/wget" <<'SH'
#!/bin/sh
[ "${MOCK_MODE:-}" != importer-unavailable ]
SH
chmod +x "$FAKE_BIN/wget"

cat > "$APP/config" <<'EOF'
REMOTE_SHARE_HOSTNAME=test-tablet
REMOTE_SHARE_PORT=8080
AUTO_OFF_SECONDS=60
EOF

COMMON_ENV=(
    PATH="$FAKE_BIN:$PATH"
    REMOTE_SHARE_BASE="$APP"
    REMOTE_SHARE_CONTROL_PATH="$APP/remote-share-control"
)

run_control() {
    env "${COMMON_ENV[@]}" "$APP/remote-share-control" "$@"
}

assert_off_and_clean() {
    [ "$(run_control status-fast)" = OFF ]
    [ ! -e "$APP/run/tailscaled.pid" ]
    [ ! -S "$APP/run/tailscaled.sock" ]
}

echo 'controller: successful ON/OFF'
output=$(run_control on)
case "$output" in 'ON expires='*' url=http://192.0.2.24:8080/') ;; *) echo "unexpected output: $output" >&2; exit 1 ;; esac
[ "$(run_control status-fast)" != OFF ]
run_control off >/dev/null
assert_off_and_clean

echo 'controller: authentication required'
if MOCK_MODE=auth-required run_control on >/dev/null 2>&1; then exit 1; fi
assert_off_and_clean

echo 'controller: successful interactive authentication leaves sharing off'
[ "$(run_control auth)" = AUTHENTICATED ]
assert_off_and_clean

echo 'controller: daemon failure'
if MOCK_MODE=daemon-failure run_control on >/dev/null 2>&1; then exit 1; fi
assert_off_and_clean

echo 'controller: importer unavailable'
if MOCK_MODE=importer-unavailable run_control on >/dev/null 2>&1; then exit 1; fi
assert_off_and_clean

echo 'controller: Tailscale failure'
if MOCK_MODE=tailscale-failure run_control on >/dev/null 2>&1; then exit 1; fi
assert_off_and_clean

echo 'controller: Serve failure and partial-start cleanup'
if MOCK_MODE=serve-failure run_control on >/dev/null 2>&1; then exit 1; fi
assert_off_and_clean

echo 'controller: timeout path'
run_control on >/dev/null
run_control expire >/dev/null
assert_off_and_clean

echo 'controller: stale PID file'
printf '%s\n' 999999 > "$APP/run/tailscaled.pid"
printf '%s\n' 'ON expires=9999999999 url=http://192.0.2.24:8080/' > "$APP/run/status"
[ "$(run_control status-fast)" = OFF ]
run_control off >/dev/null

echo 'controller tests passed'
