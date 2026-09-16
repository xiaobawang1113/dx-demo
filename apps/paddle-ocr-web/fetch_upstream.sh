#!/usr/bin/env bash
# Fetch pinned upstream OCR repos into python/ (not committed — see board/overlay).
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
PY_DIR="${APP_DIR}/python"
LOCK="${APP_DIR}/upstream.lock"
WEB_DIR="${PY_DIR}/PP-OCRv5_Online_demo-deepx"
SERVER_DIR="${PY_DIR}/PaddleOCR-deepx"

# shellcheck disable=SC1091
source "${LOCK}"

fetch_one() {
    local name="$1" repo="$2" branch="$3" commit="$4" dest="$5"
    echo "=== ${name} -> ${dest} ==="
    if [ -d "${dest}/.git" ]; then
        echo "Already a git checkout: ${dest}"
        if [ -n "${commit}" ]; then
            (cd "${dest}" && git fetch --depth 1 origin "${commit}" && git checkout FETCH_HEAD)
        else
            (cd "${dest}" && git fetch origin "${branch}" && git checkout "${branch}" && git pull --ff-only origin "${branch}" 2>/dev/null || true)
        fi
        return
    fi
    if [ -d "${dest}" ] && [ ! -d "${dest}/.git" ]; then
        echo "Removing non-git tree at ${dest} (was vendored into dx-demo; use upstream checkout)."
        rm -rf "${dest}"
    fi
    if [ -n "${commit}" ]; then
        git clone --depth 1 "${repo}" "${dest}"
        (cd "${dest}" && git fetch --depth 1 origin "${commit}" && git checkout FETCH_HEAD)
    else
        git clone --depth 1 --branch "${branch}" "${repo}" "${dest}"
    fi
    echo "OK $(cd "${dest}" && git rev-parse --short HEAD)"
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Need: $1" >&2; exit 1; }; }
need_cmd git

fetch_one "PP-OCRv5 Web UI" "${PP-OCRv5_Online_demo-deepx_REPO}" \
    "${PP-OCRv5_Online_demo-deepx_BRANCH}" "${PP-OCRv5_Online_demo-deepx_COMMIT:-}" "${WEB_DIR}"
fetch_one "PaddleOCR-deepx server" "${PaddleOCR-deepx_REPO}" \
    "${PaddleOCR-deepx_BRANCH}" "${PaddleOCR-deepx_COMMIT:-}" "${SERVER_DIR}"

echo "Upstream fetch done. Run: ${APP_DIR}/apply_board_overlay.sh"
