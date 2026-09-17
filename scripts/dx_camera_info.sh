#!/usr/bin/env bash
# Print resolved camera settings (after profile + auto-detect).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/toolchain.env"
echo "DX_DEMO_PROFILE=${DX_DEMO_PROFILE:-?}"
echo "DX_CAMERA_IDX=${DX_CAMERA_IDX:-?}"
echo "DX_CAMERA_DEV=${DX_CAMERA_DEV:-?}"
echo "DX_CAMERA_BACKEND=${DX_CAMERA_BACKEND:-?}"
echo "DX_CAMERA_FOURCC=${DX_CAMERA_FOURCC:-?}"
echo "DX_CAMERA_WIDTH=${DX_CAMERA_WIDTH:-?}"
echo "DX_CAMERA_HEIGHT=${DX_CAMERA_HEIGHT:-?}"
if command -v v4l2-ctl >/dev/null 2>&1; then
    echo "--- v4l2-ctl --list-devices ---"
    v4l2-ctl --list-devices 2>/dev/null || true
fi
