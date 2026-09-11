#!/usr/bin/env bash
set -euo pipefail

pkill -TERM -f 'cam_ppocr_v6_demo' 2>/dev/null || true
# The DX_BACKEND=python path runs demo-ocr.py; without this a leftover instance
# keeps /dev/video0 open and the next run fails to grab the camera.
pkill -TERM -f 'demo-ocr\.py' 2>/dev/null || true
# Do not match generic app.py / ocr_service.py here — that kills the OCR Web
# stack whenever the launcher starts (kill_all.sh -> this script).
pkill -TERM -f 'chrome' 2>/dev/null || true
pkill -TERM -f 'chromium' 2>/dev/null || true

