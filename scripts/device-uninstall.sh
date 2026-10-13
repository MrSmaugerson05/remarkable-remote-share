#!/bin/bash
set -euo pipefail

readonly HOME_ROOT=/home/root
readonly APP_DIR=$HOME_ROOT/remote-share
readonly QMD_TARGET=$HOME_ROOT/xovi/exthome/qt-resource-rebuilder/remoteShare.qmd
readonly EXT_TARGET=$HOME_ROOT/xovi/extensions.d/loopback-importer.so

if systemctl show xochitl.service -p Environment --value 2>/dev/null |
    grep -Fq 'LD_PRELOAD=/home/root/xovi/xovi.so'; then
    echo 'Uninstall stopped: XOVI is active. Reboot with XOVI disabled, then retry.' >&2
    exit 1
fi

if [ -x "$APP_DIR/remote-share-control" ]; then
    "$APP_DIR/remote-share-control" off >/dev/null 2>&1 || true
fi

rm -f "$QMD_TARGET" "$EXT_TARGET"
rm -rf "$APP_DIR"

echo 'Remote Share files and local Tailscale node state were removed.'
echo 'Reboot the tablet, then revoke this tablet in the Tailscale admin console.'
echo 'The compatible XOVI, QTRR, and Vellum installation was not changed.'
