#!/usr/bin/env bash
# Deprecated name — use verify_compatible.sh (Compatible Mode, SDK 2.3.x).
exec "$(cd "$(dirname "$0")" && pwd)/verify_compatible.sh" "$@"
