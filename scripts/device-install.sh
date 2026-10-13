#!/bin/bash
set -euo pipefail

readonly HOME_ROOT=/home/root
readonly APP_DIR=$HOME_ROOT/remote-share
readonly QMD_DIR=$HOME_ROOT/xovi/exthome/qt-resource-rebuilder
readonly EXT_DIR=$HOME_ROOT/xovi/extensions.d
readonly QMD_TARGET=$QMD_DIR/remoteShare.qmd
readonly EXT_TARGET=$EXT_DIR/loopback-importer.so
readonly APK_DB=$HOME_ROOT/.vellum/lib/apk/db/installed
readonly HASHTAB=$HOME_ROOT/xovi/exthome/qt-resource-rebuilder/hashtab
readonly COMMAND_EXECUTOR=$EXT_DIR/qt-command-executor.so
readonly BACKUP_ROOT=$HOME_ROOT/remote-share-backups
PAYLOAD_VERSION=

fail() {
    echo "Install stopped: $*" >&2
    exit 1
}

package_version() {
    local package=$1
    awk -F: -v wanted="$package" '
        $1 == "P" { current=$2 }
        $1 == "V" && current == wanted { print $2; exit }
    ' "$APK_DB"
}

xovi_is_active() {
    systemctl show xochitl.service -p Environment --value 2>/dev/null |
        grep -Fq 'LD_PRELOAD=/home/root/xovi/xovi.so'
}

check_compatibility() {
    local model arch os xovi qtrr extensions
    model=$(tr -d '\000' < /proc/device-tree/model)
    arch=$(uname -m)
    # shellcheck source=/dev/null
    source /etc/os-release
    os=${VERSION_ID:-}

    [ "$model" = 'reMarkable Ferrari' ] || fail "unsupported model: $model"
    [ "$arch" = 'aarch64' ] || fail "unsupported architecture: $arch"
    [ "$os" = '3.28.0.172' ] || fail "unsupported OS: $os"
    [ -r "$APK_DB" ] || fail 'the Vellum package database is missing'

    xovi=$(package_version xovi)
    qtrr=$(package_version qt-resource-rebuilder)
    extensions=$(package_version xovi-extensions)
    [ "$xovi" = '0.3.3-r2' ] || fail "XOVI 0.3.3-r2 is required (found ${xovi:-none})"
    [ "$qtrr" = '19.0.0-r4' ] || fail "qt-resource-rebuilder 19.0.0-r4 is required (found ${qtrr:-none})"
    [ "$extensions" = '19.0.0-r4' ] || fail "xovi-extensions 19.0.0-r4 is required (found ${extensions:-none})"
    [ -s "$COMMAND_EXECUTOR" ] || fail 'qt-command-executor is missing'
    [ -s "$HASHTAB" ] || fail 'the QTRR hashtable is missing'
    grep -aFq '3.28.0.172' "$HASHTAB" || fail 'the QTRR hashtable is not for OS 3.28.0.172'
    ! xovi_is_active || fail 'XOVI is active; reboot with XOVI disabled before installing'
}

check_payload() {
    local payload=$1 file
    for file in remote-share-control remoteShare.qmd loopback-importer.so config.example \
        compatibility.env device-uninstall.sh VERSION tailscale tailscaled; do
        [ -s "$payload/$file" ] || fail "payload file is missing: $file"
    done
    PAYLOAD_VERSION=$(awk -F= '$1 == "PROJECT_VERSION" { print $2; exit }' "$payload/compatibility.env")
    printf '%s\n' "$PAYLOAD_VERSION" | grep -Eq '^[0-9]+[.][0-9]+[.][0-9]+$' ||
        fail 'compatibility.env has an invalid PROJECT_VERSION'
    [ "$(cat "$payload/VERSION")" = "$PAYLOAD_VERSION" ] ||
        fail 'VERSION does not match compatibility.env'
}

restore_backup() {
    local backup=$1
    rm -rf "$APP_DIR" "$QMD_TARGET" "$EXT_TARGET"
    [ ! -e "$backup/remote-share" ] || cp -a "$backup/remote-share" "$APP_DIR"
    [ ! -e "$backup/remoteShare.qmd" ] || cp -a "$backup/remoteShare.qmd" "$QMD_TARGET"
    [ ! -e "$backup/loopback-importer.so" ] || cp -a "$backup/loopback-importer.so" "$EXT_TARGET"
}

install_payload() {
    local payload=$1 stamp backup new_dir
    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    backup=$BACKUP_ROOT/$stamp
    new_dir=$HOME_ROOT/.remote-share-new-$stamp

    mkdir -p "$backup" "$new_dir/bin" "$new_dir/run" "$new_dir/state"
    chmod 700 "$BACKUP_ROOT" "$backup" "$new_dir" "$new_dir/bin" "$new_dir/run" "$new_dir/state"
    [ ! -e "$APP_DIR" ] || cp -a "$APP_DIR" "$backup/remote-share"
    [ ! -e "$QMD_TARGET" ] || cp -a "$QMD_TARGET" "$backup/remoteShare.qmd"
    [ ! -e "$EXT_TARGET" ] || cp -a "$EXT_TARGET" "$backup/loopback-importer.so"

    trap 'restore_backup "$backup"; rm -rf "$new_dir"; echo "Install failed; previous files restored." >&2' ERR
    if [ -x "$APP_DIR/remote-share-control" ]; then
        "$APP_DIR/remote-share-control" off >/dev/null 2>&1 || true
    fi

    install -m 0755 "$payload/remote-share-control" "$new_dir/remote-share-control"
    install -m 0755 "$payload/tailscale" "$new_dir/bin/tailscale"
    install -m 0755 "$payload/tailscaled" "$new_dir/bin/tailscaled"
    install -m 0755 "$payload/device-uninstall.sh" "$new_dir/uninstall"
    install -m 0644 "$payload/compatibility.env" "$new_dir/compatibility.env"
    install -m 0644 "$payload/VERSION" "$new_dir/VERSION"

    if [ -f "$APP_DIR/config" ]; then
        install -m 0600 "$APP_DIR/config" "$new_dir/config"
    else
        install -m 0600 "$payload/config.example" "$new_dir/config"
    fi
    if [ -d "$APP_DIR/state" ]; then
        cp -a "$APP_DIR/state/." "$new_dir/state/"
        chmod 700 "$new_dir/state"
    fi

    mkdir -p "$QMD_DIR" "$EXT_DIR"
    install -m 0644 "$payload/remoteShare.qmd" "$QMD_TARGET"
    install -m 0755 "$payload/loopback-importer.so" "$EXT_TARGET"
    rm -rf "$APP_DIR"
    mv "$new_dir" "$APP_DIR"
    "$APP_DIR/remote-share-control" off >/dev/null
    trap - ERR

    echo "Installed Remote Share $PAYLOAD_VERSION. Sharing is OFF."
    echo "Backup of replaced files: $backup"
    echo 'Reboot the tablet before authenticating so XOVI loads the new QMD and importer.'
}

[ "$(id -u)" -eq 0 ] || fail 'run this installer as root'
[ "$#" -eq 1 ] || fail "usage: $0 PAYLOAD_DIRECTORY"
[ -d "$1" ] || fail "payload directory does not exist: $1"
check_compatibility
check_payload "$1"
install_payload "$1"
