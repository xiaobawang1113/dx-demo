#!/usr/bin/env bash
set -euo pipefail

# Terminate the PP-OCRv5 web stack:
#   app.py          (Gradio UI, port 7860)
#   ocr_service.py  (PaddleOCR-deepx FastAPI server, port 8080)
#   run.sh parent   (setsid wrapper that owns uvicorn)
#   the browser window opened by run_ocr_web.sh (PID recorded at launch)
#
# The python processes are matched by their full script paths: a loose pattern
# such as 'app.py' also hits unrelated shells and editors. The browser is killed
# by recorded PID for the same reason - matching the URL would kill any shell
# whose command line happens to mention it, and leaves other windows alone.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BROWSER_PID_FILE="${ROOT_DIR}/apps/paddle-ocr-web/.browser.pid"

pkill -TERM -f 'PP-OCRv5_Online_demo-deepx/app\.py' 2>/dev/null || true
pkill -TERM -f 'deploy/fastapi/ocr_service\.py' 2>/dev/null || true
pkill -TERM -f 'deploy/fastapi/run\.sh' 2>/dev/null || true

if [ -f "${BROWSER_PID_FILE}" ]; then
    kill -TERM "$(cat "${BROWSER_PID_FILE}")" 2>/dev/null || true
    rm -f "${BROWSER_PID_FILE}"
fi

wait_port_free() {
    local port="$1"
    local i pid
    for i in $(seq 1 25); do
        if ! ss -lnt 2>/dev/null | grep -q ":${port} "; then
            return 0
        fi
        sleep 0.2
    done
    pid="$(ss -lntp 2>/dev/null | awk -v p=":${port}" '$0 ~ p {print}' | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | head -1)"
    if [ -n "${pid}" ]; then
        kill -KILL "${pid}" 2>/dev/null || true
    fi
}

wait_port_free 8080
wait_port_free 7860

pkill -KILL -f 'PP-OCRv5_Online_demo-deepx/app\.py' 2>/dev/null || true
pkill -KILL -f 'deploy/fastapi/ocr_service\.py' 2>/dev/null || true
