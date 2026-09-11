#!/bin/bash

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${ROOT_DIR}/apps/paddle-ocr-web"

if [ -f "${ROOT_DIR}/toolchain.env" ]; then
    # shellcheck disable=SC1091
    source "${ROOT_DIR}/toolchain.env"
fi

# Load top-level configuration
if [ -f "${ROOT_DIR}/config.sh" ]; then
    source "${ROOT_DIR}/config.sh"
fi

"${ROOT_DIR}"/scripts/kill_ocr_web.sh

PY_DIR="${APP_DIR}/python"
WEB_DIR="${PY_DIR}/PP-OCRv5_Online_demo-deepx"
VENV_DIR="${PY_DIR}/.venv"

SERVER_DIR="${PY_DIR}/PaddleOCR-deepx"
FASTAPI_DIR="${SERVER_DIR}/deploy/fastapi"

OCR_API_URL="${DX_OCR_API_URL:-http://localhost:8080/api/v1/ocr}"
OCR_HEALTH_URL="${OCR_API_URL%/api/v1/ocr}/health"
# app.py pins server_port=7860 in demo.launch(), so the port is not configurable
WEB_URL="http://localhost:7860"

# Auto-setup on first run. Vendored sources are in git; still need venvs +
# dx-engine 3.3.0 + server .dxnn. Prefer scripts/setup_repro.sh on a new board.
if [ ! -f "${WEB_DIR}/app.py" ] || [ ! -x "${VENV_DIR}/bin/python" ] || [ ! -x "${FASTAPI_DIR}/venv/bin/python" ]; then
    echo "Web demo environment not found. Running python/build.sh ..."
    _dx_rt_arg=()
    if [ -d "${PY_DIR}/.cache/dx_rt-3.3.0/python_package" ]; then
        _dx_rt_arg=(--dx_rt "${PY_DIR}/.cache/dx_rt-3.3.0")
    elif [ -n "${DX_RT_PATH:-}" ]; then
        _dx_rt_arg=(--dx_rt "${DX_RT_PATH}")
    fi
    if ! "${PY_DIR}"/build.sh "${_dx_rt_arg[@]}"; then
        echo "Error: setup failed. On a new machine run: ${ROOT_DIR}/scripts/setup_repro.sh"
        read -t 3 -p "Press enter to exit..." || true
        exit 1
    fi
fi

# PaddleX reads PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK, not DISABLE_MODEL_SOURCE_CHECK.
# Without this, startup hangs probing HuggingFace. Default mobile weights are not
# cached here; --use-server uses the local PP-OCRv5_server_* models. --lazy-load
# Paddle on this board SIGSEGV's if the first PaddleOCR() runs inside a
# FastAPI worker thread (lazy-load). Preload on the main thread instead.
export PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True
export DISABLE_MODEL_SOURCE_CHECK=True
export FLAGS_use_mkldnn=0
export OMP_NUM_THREADS=1
export PADDLE_NUM_THREADS=1
# --lazy-load: do not construct PaddleOCR at startup (CPU init SIGSEGVs here).
# NPU models load on the first deepx=true request via dx_engine 3.3.0.
OCR_MODEL_ARGS=(--use-server --lazy-load)

# Detach children from this script's process group. Otherwise closing the
# launcher script, a terminal, or an agent job sends SIGHUP/SIGTERM to
# uvicorn and it exits cleanly ("Shutting down") even though OCR is fine.
start_detached() {
    local log="$1"
    shift
    nohup setsid "$@" >>"${log}" 2>&1 < /dev/null &
    disown $! 2>/dev/null || true
}

API_LOG="${APP_DIR}/.ocr-api.log"
UI_LOG="${APP_DIR}/.ocr-ui.log"

# kill_ocr_web.sh now waits until 8080 is free. Only reuse an API that is
# still healthy *after* that wait — never a process that is about to exit.
if curl -sf -m 2 "${OCR_HEALTH_URL}" > /dev/null 2>&1; then
    echo "OCR server already running at ${OCR_API_URL}"
elif [ -x "${FASTAPI_DIR}/run.sh" ] && [ -x "${FASTAPI_DIR}/venv/bin/python" ]; then
    echo "Starting OCR server (server models, local cache, lazy load) ..."
    : > "${API_LOG}"
    (
        cd "${FASTAPI_DIR}"
        nohup setsid ./run.sh "${OCR_MODEL_ARGS[@]}" >>"${API_LOG}" 2>&1 < /dev/null &
        disown $! 2>/dev/null || true
    )

    echo "Waiting for the OCR server ..."
    _api_up=0
    for _ in $(seq 1 180); do
        if curl -sf -m 2 "${OCR_HEALTH_URL}" > /dev/null 2>&1; then
            _api_up=1
            break
        fi
        sleep 1
    done
    if [ "${_api_up}" != "1" ]; then
        echo "Error: OCR server did not become healthy on ${OCR_HEALTH_URL}"
        echo "       See ${API_LOG}"
    fi
else
    echo "Warning: no OCR server at ${OCR_API_URL} and no local PaddleOCR-deepx setup."
    echo "         The UI will start, but OCR requests will fail."
    echo "         Use the card's \"OCR Server\" button or see apps/paddle-ocr-web/README.md."
fi

echo "Running Python backend..."
# Gradio allowed_paths is checked against cwd. Start from WEB_DIR so example
# images/PDFs are readable after a launcher restart.
: > "${UI_LOG}"
(
    cd "${WEB_DIR}"
    nohup setsid env API_URL="${OCR_API_URL}" \
        "${VENV_DIR}"/bin/python "${WEB_DIR}"/app.py >>"${UI_LOG}" 2>&1 < /dev/null &
    disown $! 2>/dev/null || true
)

# app.py runs with inbrowser=False, so open the page once the port answers
echo "Waiting for ${WEB_URL} ..."
for _ in $(seq 1 120); do
    curl -sf -m 2 "${WEB_URL}" > /dev/null 2>&1 && break
    sleep 1
done

"${ROOT_DIR}"/scripts/open_browser.sh --no-fullscreen "${WEB_URL}" &
# open_browser.sh execs the browser, so $! is the browser itself
echo $! > "${APP_DIR}/.browser.pid"

# Let the launcher end its "Wait" as soon as the page is actually up
if [ -n "${DX_LAUNCHER_READY_FILE:-}" ]; then
    : > "${DX_LAUNCHER_READY_FILE}"
fi
