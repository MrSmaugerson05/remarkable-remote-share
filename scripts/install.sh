#!/bin/bash
set -euo pipefail

VERSION=0.1.0
PROJECT=MrSmaugerson05/remarkable-remote-share
TAILSCALE_VERSION=1.104.1
TAILSCALE_SHA256=f60294374967f3dfd8cf57bbbd474d6cfce32d123e3a8ddeab82a87940daa806

usage() {
    echo "usage: $0 DEVICE_HOST SSH_IDENTITY" >&2
    exit 2
}

[ "$#" -eq 2 ] || usage
DEVICE_HOST=$1
IDENTITY=$2
case "$DEVICE_HOST" in *[!A-Za-z0-9.:-]*|'') usage ;; esac
[ -f "$IDENTITY" ] || { echo "SSH identity file not found: $IDENTITY" >&2; exit 1; }
for command in ssh scp curl tar sha256sum; do
    command -v "$command" >/dev/null || { echo "required command is missing: $command" >&2; exit 1; }
done

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/remarkable-remote-share.XXXXXXXX")
REMOTE_STAGE=/home/root/remote-share-upload-$(date +%s)-$$
TARGET=root@$DEVICE_HOST
SSH_ARGS=(-o BatchMode=yes -o IdentitiesOnly=yes -i "$IDENTITY")

cleanup() {
    ssh "${SSH_ARGS[@]}" "$TARGET" rm -rf -- "$REMOTE_STAGE" >/dev/null 2>&1 || true
    case "$TEMP_ROOT" in
        "${TMPDIR:-/tmp}"/remarkable-remote-share.*) rm -rf "$TEMP_ROOT" ;;
    esac
}
trap cleanup EXIT

ARCHIVE=$TEMP_ROOT/remarkable-remote-share-$VERSION.tar.gz
BASE=https://github.com/$PROJECT/releases/download/v$VERSION
curl --fail --location --proto '=https' --tlsv1.2 --output "$ARCHIVE" "$BASE/remarkable-remote-share-$VERSION.tar.gz"
curl --fail --location --proto '=https' --tlsv1.2 --output "$TEMP_ROOT/SHA256SUMS" "$BASE/SHA256SUMS"
expected=$(awk -v file="remarkable-remote-share-$VERSION.tar.gz" '$2 == file { print $1; exit }' "$TEMP_ROOT/SHA256SUMS")
[ -n "$expected" ] || { echo 'release checksum is missing' >&2; exit 1; }
printf '%s  %s\n' "$expected" "$ARCHIVE" | sha256sum --check --status

TS_ARCHIVE=$TEMP_ROOT/tailscale_$TAILSCALE_VERSION-arm64.tgz
curl --fail --location --proto '=https' --tlsv1.2 \
    --output "$TS_ARCHIVE" "https://pkgs.tailscale.com/stable/tailscale_$TAILSCALE_VERSION"_arm64.tgz
printf '%s  %s\n' "$TAILSCALE_SHA256" "$TS_ARCHIVE" | sha256sum --check --status

tar -xzf "$ARCHIVE" -C "$TEMP_ROOT"
tar -xzf "$TS_ARCHIVE" -C "$TEMP_ROOT"
PAYLOAD=$TEMP_ROOT/remarkable-remote-share-$VERSION
cp "$TEMP_ROOT/tailscale_$TAILSCALE_VERSION"_arm64/tailscale "$PAYLOAD/"
cp "$TEMP_ROOT/tailscale_$TAILSCALE_VERSION"_arm64/tailscaled "$PAYLOAD/"

ssh "${SSH_ARGS[@]}" "$TARGET" install -d -m 700 "$REMOTE_STAGE"
scp -q "${SSH_ARGS[@]}" -r "$PAYLOAD/." "$TARGET:$REMOTE_STAGE/"
ssh "${SSH_ARGS[@]}" "$TARGET" sh -s -- "$REMOTE_STAGE" <<'REMOTE'
set -eu
stage=$1
chmod 755 "$stage/device-install.sh"
"$stage/device-install.sh" "$stage"
REMOTE

echo
echo 'Tailscale authentication is interactive. Open the URL printed below in your browser.'
ssh "${SSH_ARGS[@]}" -t "$TARGET" /home/root/remote-share/remote-share-control auth
ssh "${SSH_ARGS[@]}" "$TARGET" /home/root/remote-share/remote-share-control off
echo 'Installation finished. Sharing is OFF. Reboot with the normal three-button XOVI start sequence.'
