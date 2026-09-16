#!/usr/bin/env bash
# Copy Firefly / M1 board adaptations onto upstream OCR checkouts.
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
OVERLAY="${APP_DIR}/board/overlay"
PY_DIR="${APP_DIR}/python"

if [ ! -d "${OVERLAY}" ]; then
    echo "No board overlay at ${OVERLAY}" >&2
    exit 1
fi
for dest in "${PY_DIR}/PP-OCRv5_Online_demo-deepx" "${PY_DIR}/PaddleOCR-deepx"; do
    if [ ! -d "${dest}" ]; then
        echo "Missing ${dest}. Run ${APP_DIR}/fetch_upstream.sh first." >&2
        exit 1
    fi
done

echo "Applying board overlay from ${OVERLAY} ..."
# overlay layout mirrors upstream repo roots (PP-OCRv5_Online_demo-deepx/, PaddleOCR-deepx/)
cp -a "${OVERLAY}/PP-OCRv5_Online_demo-deepx/." "${PY_DIR}/PP-OCRv5_Online_demo-deepx/"
cp -a "${OVERLAY}/PaddleOCR-deepx/." "${PY_DIR}/PaddleOCR-deepx/"
echo "Board overlay applied."
