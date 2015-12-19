#!/bin/bash
set -eu
set -o pipefail
export PYTHONPATH="/app/libs/IOPi/:/app/libs/ADCPi/:${PYTHONPATH:-}"
python "$@" 2>&1 | logger
