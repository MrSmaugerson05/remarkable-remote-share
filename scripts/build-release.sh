#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(awk -F= '$1 == "PROJECT_VERSION" { print $2; exit }' "$ROOT/compatibility.env")
if ! printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+[.][0-9]+[.][0-9]+$'; then
    echo 'PROJECT_VERSION is not a release version' >&2
    exit 1
fi
OUTPUT=${1:-$ROOT/dist}
STAGE=$OUTPUT/remarkable-remote-share-$VERSION

[ -s "$ROOT/build/loopback-importer.so" ] || {
    echo 'build/loopback-importer.so is missing' >&2
    exit 1
}

rm -rf "$STAGE"
mkdir -p "$STAGE"
install -m 0755 "$ROOT/src/controller/remote-share-control" "$STAGE/remote-share-control"
install -m 0644 "$ROOT/src/qmd/remoteShare.qmd" "$STAGE/remoteShare.qmd"
install -m 0755 "$ROOT/build/loopback-importer.so" "$STAGE/loopback-importer.so"
install -m 0644 "$ROOT/config.example" "$STAGE/config.example"
install -m 0644 "$ROOT/compatibility.env" "$STAGE/compatibility.env"
install -m 0755 "$ROOT/scripts/device-install.sh" "$STAGE/device-install.sh"
install -m 0755 "$ROOT/scripts/device-uninstall.sh" "$STAGE/device-uninstall.sh"
printf '%s\n' "$VERSION" > "$STAGE/VERSION"

tar --sort=name --mtime='UTC 2026-01-01' --owner=0 --group=0 --numeric-owner \
    -czf "$OUTPUT/remarkable-remote-share-$VERSION.tar.gz" -C "$OUTPUT" "remarkable-remote-share-$VERSION"
(
    cd "$OUTPUT"
    sha256sum "remarkable-remote-share-$VERSION.tar.gz" > SHA256SUMS
)
