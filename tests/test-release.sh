#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
ARCHIVE=${1:-$ROOT/dist/remarkable-remote-share-0.1.0.tar.gz}
TEMP=$(mktemp -d "${TMPDIR:-/tmp}/remote-share-release.XXXXXXXX")
trap 'case "$TEMP" in "${TMPDIR:-/tmp}"/remote-share-release.*) rm -rf "$TEMP" ;; esac' EXIT

[ -s "$ARCHIVE" ]
tar -tzf "$ARCHIVE" | LC_ALL=C sort > "$TEMP/actual"
cat > "$TEMP/expected" <<'EOF'
remarkable-remote-share-0.1.0/
remarkable-remote-share-0.1.0/VERSION
remarkable-remote-share-0.1.0/compatibility.env
remarkable-remote-share-0.1.0/config.example
remarkable-remote-share-0.1.0/device-install.sh
remarkable-remote-share-0.1.0/device-uninstall.sh
remarkable-remote-share-0.1.0/loopback-importer.so
remarkable-remote-share-0.1.0/remote-share-control
remarkable-remote-share-0.1.0/remoteShare.qmd
EOF
LC_ALL=C sort -o "$TEMP/expected" "$TEMP/expected"
diff -u "$TEMP/expected" "$TEMP/actual"

if tar -xOf "$ARCHIVE" remarkable-remote-share-0.1.0/compatibility.env |
    grep -Eq 'authkey|login-server|private'; then
    echo 'release contains an unexpected sensitive setting' >&2
    exit 1
fi

echo 'release allowlist test passed'
