#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODE=${1:-working}
MANIFEST=$ROOT/.public-files
LOCAL_PATTERNS=${REMOTE_SHARE_PRIVATE_PATTERNS_FILE:-$ROOT/.privacy-local-patterns}
TEMP=$(mktemp -d "${TMPDIR:-/tmp}/remote-share-privacy.XXXXXXXX")
trap 'case "$TEMP" in "${TMPDIR:-/tmp}"/remote-share-privacy.*) rm -rf "$TEMP" ;; esac' EXIT

mail_a=gma
domain_tail='il[.]com'
network_suffix='[.]ts[.]net'
address_prefix='100[.][0-9]{1,3}[.][0-9]{1,3}[.][0-9]{1,3}'
key_prefix='tskey'
key_suffix='-'
state_a=tailscaled
state_b='[.]state'
private_a='BEGIN.*PRIVATE'
private_b='KEY'
forbidden="@${mail_a}${domain_tail}|[A-Za-z]:[/\\\\]Users[/\\\\]|${network_suffix}|${address_prefix}|${key_prefix}${key_suffix}|${private_a} ${private_b}|${state_a}${state_b}"

# Exact personal identifiers belong in an ignored local file, one ERE per line.
# History uses only generic rules because local identifiers may already occur in
# old public commits; working and staged scans prevent introducing them again.
if [ "$MODE" != history ] && [ -r "$LOCAL_PATTERNS" ]; then
    local_forbidden=$(sed -E '/^[[:space:]]*(#|$)/d' "$LOCAL_PATTERNS" | paste -sd '|' -)
    [ -z "$local_forbidden" ] || forbidden="$forbidden|$local_forbidden"
fi

cd "$ROOT"
case "$MODE" in
    working)
        git ls-files --cached --others --exclude-standard | LC_ALL=C sort -u > "$TEMP/files"
        cp "$TEMP/files" "$TEMP/names"
        while IFS= read -r file; do
            [ -f "$file" ] || continue
            grep -IEn "$forbidden" "$file" && { echo "privacy check failed in $file" >&2; exit 1; }
        done < "$TEMP/files"
        ;;
    staged)
        git ls-files | LC_ALL=C sort -u > "$TEMP/files"
        cp "$TEMP/files" "$TEMP/names"
        while IFS= read -r file; do
            git show ":$file" > "$TEMP/content"
            grep -IEn "$forbidden" "$TEMP/content" && { echo "privacy check failed in staged file $file" >&2; exit 1; }
        done < "$TEMP/files"
        ;;
    history)
        git log --all --format= --name-only | sed '/^$/d' | LC_ALL=C sort -u > "$TEMP/names"
        if git rev-parse --verify HEAD >/dev/null 2>&1; then
            mapfile -t commits < <(git rev-list --all)
            git grep -IEn "$forbidden" "${commits[@]}" && { echo 'privacy check failed in Git history' >&2; exit 1; }
        fi
        ;;
    *) echo "usage: $0 {working|staged|history}" >&2; exit 2 ;;
esac

LC_ALL=C sort -u "$MANIFEST" > "$TEMP/allowed"
if ! diff -u "$TEMP/allowed" "$TEMP/names"; then
    echo "privacy check failed: $MODE file list differs from .public-files" >&2
    exit 1
fi

if grep -E '\.(o|so|a|exe|zip|tgz|tar|gz)$|(^|/)(build|dist|state|run|evidence|research)/|hashtab' "$TEMP/names"; then
    echo 'privacy check failed: generated, private, or binary material is present' >&2
    exit 1
fi

echo "privacy check passed ($MODE)"
