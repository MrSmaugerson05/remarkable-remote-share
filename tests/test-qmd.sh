#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
QMD=$ROOT/src/qmd/remoteShare.qmd

[ "$(grep -c 'status-fast' "$QMD")" -eq 1 ]
grep -Fq 'repeat: false; running: true' "$QMD"
grep -Fq 'remoteShareExpiryTimer.restart()' "$QMD"
grep -Fq 'remoteShareExpiryTimer.stop()' "$QMD"
grep -Fq '7424602933551009652' "$QMD"
grep -Fq '3799445540336449548' "$QMD"
grep -Fq '6968812125536432958' "$QMD"
grep -Fq '18215817719560467479' "$QMD"

echo 'QMD static tests passed'
