#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PROJECT_VERSION=$(awk -F= '$1 == "PROJECT_VERSION" { print $2; exit }' "$ROOT/compatibility.env")
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/remote-share-installer.XXXXXXXX")
FIXTURE=$TEST_ROOT/rootfs
PAYLOAD=$TEST_ROOT/payload
MOCK_BIN=$TEST_ROOT/mock-bin
INSTALLER=$TEST_ROOT/device-install.sh
UNINSTALLER=$TEST_ROOT/device-uninstall.sh

cleanup() {
    case "$TEST_ROOT" in "${TMPDIR:-/tmp}"/remote-share-installer.*) rm -rf "$TEST_ROOT" ;; esac
}
trap cleanup EXIT

rewrite_script() {
    sed \
        -e "s|/home/root|$FIXTURE/home/root|g" \
        -e "s|/proc/device-tree/model|$FIXTURE/proc/device-tree/model|g" \
        -e "s|/etc/os-release|$FIXTURE/etc/os-release|g" \
        "$1" > "$2"
    chmod +x "$2"
}

reset_fixture() {
    rm -rf "$FIXTURE" "$PAYLOAD"
    mkdir -p "$FIXTURE/proc/device-tree" "$FIXTURE/etc" \
        "$FIXTURE/home/root/.vellum/lib/apk/db" \
        "$FIXTURE/home/root/xovi/extensions.d" \
        "$FIXTURE/home/root/xovi/exthome/qt-resource-rebuilder" \
        "$PAYLOAD"
    printf '%s' 'reMarkable Ferrari' > "$FIXTURE/proc/device-tree/model"
    printf '%s\n' 'VERSION_ID=3.28.0.172' > "$FIXTURE/etc/os-release"
    cat > "$FIXTURE/home/root/.vellum/lib/apk/db/installed" <<'EOF'
P:xovi
V:0.3.3-r2

P:qt-resource-rebuilder
V:19.0.0-r4

P:xovi-extensions
V:19.0.0-r4
EOF
    printf 'executor' > "$FIXTURE/home/root/xovi/extensions.d/qt-command-executor.so"
    printf 'table for 3.28.0.172' > "$FIXTURE/home/root/xovi/exthome/qt-resource-rebuilder/hashtab"
    for file in remoteShare.qmd loopback-importer.so config.example tailscale tailscaled; do
        printf 'fixture\n' > "$PAYLOAD/$file"
    done
    cp "$ROOT/compatibility.env" "$PAYLOAD/compatibility.env"
    cat > "$PAYLOAD/remote-share-control" <<'EOF'
#!/bin/sh
exit 0
EOF
    cp "$ROOT/scripts/device-uninstall.sh" "$PAYLOAD/device-uninstall.sh"
    printf '%s\n' "$PROJECT_VERSION" > "$PAYLOAD/VERSION"
    chmod +x "$PAYLOAD/remote-share-control" "$PAYLOAD/tailscale" "$PAYLOAD/tailscaled" "$PAYLOAD/device-uninstall.sh"
}

mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/id" <<'EOF'
#!/bin/sh
[ "${1:-}" = -u ] && echo 0
EOF
cat > "$MOCK_BIN/uname" <<'EOF'
#!/bin/sh
echo "${MOCK_ARCH:-aarch64}"
EOF
cat > "$MOCK_BIN/systemctl" <<'EOF'
#!/bin/sh
[ "${MOCK_XOVI_ACTIVE:-0}" != 1 ] || echo "LD_PRELOAD=$MOCK_XOVI_PATH"
exit 0
EOF
chmod +x "$MOCK_BIN/id" "$MOCK_BIN/uname" "$MOCK_BIN/systemctl"
rewrite_script "$ROOT/scripts/device-install.sh" "$INSTALLER"
rewrite_script "$ROOT/scripts/device-uninstall.sh" "$UNINSTALLER"

expect_failure() {
    if PATH="$MOCK_BIN:$PATH" "$INSTALLER" "$PAYLOAD" >/dev/null 2>&1; then
        echo "expected installer failure: $1" >&2
        exit 1
    fi
}

echo 'installer: correct firmware'
reset_fixture
PATH="$MOCK_BIN:$PATH" "$INSTALLER" "$PAYLOAD" >/dev/null
[ -f "$FIXTURE/home/root/remote-share/VERSION" ]

echo 'installer: wrong model'
reset_fixture
printf '%s' 'unsupported tablet' > "$FIXTURE/proc/device-tree/model"
expect_failure model

echo 'installer: wrong OS'
reset_fixture
printf '%s\n' 'VERSION_ID=0.0.0' > "$FIXTURE/etc/os-release"
expect_failure os

echo 'installer: wrong architecture'
reset_fixture
if MOCK_ARCH=armv7l PATH="$MOCK_BIN:$PATH" "$INSTALLER" "$PAYLOAD" >/dev/null 2>&1; then exit 1; fi

echo 'installer: active XOVI rejected'
reset_fixture
if MOCK_XOVI_ACTIVE=1 MOCK_XOVI_PATH="$FIXTURE/home/root/xovi/xovi.so" PATH="$MOCK_BIN:$PATH" "$INSTALLER" "$PAYLOAD" >/dev/null 2>&1; then exit 1; fi

echo 'installer: missing dependency'
reset_fixture
rm "$FIXTURE/home/root/xovi/extensions.d/qt-command-executor.so"
expect_failure dependency

echo 'installer: missing and wrong hashtable'
reset_fixture
rm "$FIXTURE/home/root/xovi/exthome/qt-resource-rebuilder/hashtab"
expect_failure missing-hashtable
reset_fixture
printf 'table for another release' > "$FIXTURE/home/root/xovi/exthome/qt-resource-rebuilder/hashtab"
expect_failure wrong-hashtable

echo 'installer: mismatched payload version'
reset_fixture
printf '%s\n' '9.9.9' > "$PAYLOAD/VERSION"
expect_failure payload-version

echo 'installer: upgrade backup'
reset_fixture
mkdir -p "$FIXTURE/home/root/remote-share"
printf 'old config\n' > "$FIXTURE/home/root/remote-share/config"
    printf 'old qmd\n' > "$FIXTURE/home/root/xovi/exthome/qt-resource-rebuilder/remoteShare.qmd"
PATH="$MOCK_BIN:$PATH" "$INSTALLER" "$PAYLOAD" >/dev/null
backup=$(find "$FIXTURE/home/root/remote-share-backups" -mindepth 1 -maxdepth 1 -type d | head -n 1)
[ "$(cat "$backup/remoteShare.qmd")" = 'old qmd' ]
[ "$(cat "$FIXTURE/home/root/remote-share/config")" = 'old config' ]

echo 'uninstaller: idempotent and scoped'
printf 'keep\n' > "$FIXTURE/home/root/xovi/keep-me"
PATH="$MOCK_BIN:$PATH" "$UNINSTALLER" >/dev/null
PATH="$MOCK_BIN:$PATH" "$UNINSTALLER" >/dev/null
[ -f "$FIXTURE/home/root/xovi/keep-me" ]
[ ! -e "$FIXTURE/home/root/remote-share" ]
[ ! -e "$FIXTURE/home/root/xovi/extensions.d/loopback-importer.so" ]
[ ! -e "$FIXTURE/home/root/xovi/exthome/qt-resource-rebuilder/remoteShare.qmd" ]

echo 'device installer tests passed'
