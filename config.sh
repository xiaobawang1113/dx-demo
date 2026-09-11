#!/bin/bash
# dx-demos top-level configuration. Safe to source after toolchain.env.
# Does not pin OS/board version — only demo defaults.

# Camera: keep an already-set DX_CAMERA_IDX (toolchain.env auto-detects).
# Firefly RK3588 HDMI RX is /dev/video0; USB webcam is usually video1.
if [ -z "${DX_CAMERA_IDX:-}" ]; then
    _board=""
    if [ -r /proc/device-tree/model ]; then
        _board="$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || true)"
    fi
    if echo "${_board}" | grep -qiE 'rk3588|firefly'; then
        export DX_CAMERA_IDX=1
    else
        export DX_CAMERA_IDX=0
    fi
    unset _board
fi
export DX_CAMERA_DEV="/dev/video${DX_CAMERA_IDX}"

# PaddleOCR-deepx server endpoint used by the OCR Web demo
export DX_OCR_API_URL="${DX_OCR_API_URL:-http://localhost:8080/api/v1/ocr}"

# Browser used by the web demos (empty = desktop default browser)
export DX_BROWSER="${DX_BROWSER:-}"
