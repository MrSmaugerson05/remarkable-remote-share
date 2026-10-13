#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(awk -F= '$1 == "PROJECT_VERSION" { print $2; exit }' "$ROOT/compatibility.env")
RELEASE=remarkable-remote-share-$VERSION
ARCHIVE=${1:-$ROOT/dist/$RELEASE.tar.gz}
TEMP=$(mktemp -d "${TMPDIR:-/tmp}/remote-share-release.XXXXXXXX")
trap 'case "$TEMP" in "${TMPDIR:-/tmp}"/remote-share-release.*) rm -rf "$TEMP" ;; esac' EXIT

[ -s "$ARCHIVE" ]
tar -tzf "$ARCHIVE" | LC_ALL=C sort > "$TEMP/actual"
for file in '' VERSION compatibility.env config.example device-install.sh device-uninstall.sh \
    loopback-importer.so remote-share-control remoteShare.qmd; do
    if [ -n "$file" ]; then
        printf '%s/%s\n' "$RELEASE" "$file"
    else
        printf '%s/\n' "$RELEASE"
    fi
done > "$TEMP/expected"
LC_ALL=C sort -o "$TEMP/expected" "$TEMP/expected"
diff -u "$TEMP/expected" "$TEMP/actual"

if tar -xOf "$ARCHIVE" "$RELEASE/compatibility.env" |
    grep -Eq 'authkey|login-server|private'; then
    echo 'release contains an unexpected sensitive setting' >&2
    exit 1
fi

echo 'release allowlist test passed'
