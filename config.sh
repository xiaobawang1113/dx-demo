#!/bin/bash
# Demo runtime config. Ensures toolchain (SDK + camera profile) is loaded once.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${REPO_ROOT}/toolchain.env" ] && [ -z "${DX_DEMO_TOOLCHAIN_LOADED:-}" ]; then
    # shellcheck source=/dev/null
    source "${REPO_ROOT}/toolchain.env"
    export DX_DEMO_TOOLCHAIN_LOADED=1
fi

export DX_OCR_API_URL="${DX_OCR_API_URL:-http://localhost:8080/api/v1/ocr}"
export DX_BROWSER="${DX_BROWSER:-}"
