#!/bin/bash
# NPU: TASK_MAX_LOAD=1 — PP-OCRv5 server models on M1 ~1.92GiB device memory.
# CPU pipeline: upstream defaults (intra=2, NFH in/out 2/4) for OCR throughput.
export CUSTOM_INTER_OP_THREADS_COUNT=1
export CUSTOM_INTRA_OP_THREADS_COUNT=2
export DXRT_DYNAMIC_CPU_THREAD=1
export DXRT_TASK_MAX_LOAD=1
export NFH_INPUT_WORKER_THREADS=2
export NFH_OUTPUT_WORKER_THREADS=4
