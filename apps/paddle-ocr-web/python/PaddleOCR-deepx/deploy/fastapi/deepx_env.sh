#!/bin/bash
# Conservative NPU buffers: M1 has 1.92GiB. Loading every PP-OCRv5
# server model with TASK_MAX_LOAD=3 overflows device memory.
export CUSTOM_INTER_OP_THREADS_COUNT=1
export CUSTOM_INTRA_OP_THREADS_COUNT=1
export DXRT_DYNAMIC_CPU_THREAD=1
export DXRT_TASK_MAX_LOAD=1
export NFH_INPUT_WORKER_THREADS=1
export NFH_OUTPUT_WORKER_THREADS=1
