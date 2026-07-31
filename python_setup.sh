#!/usr/bin/env bash
set -u

# system updates
if ! uv --version; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
else
  uv self update
fi

set -e
uv sync --no-dev
uv tree
uv run python -c "import platform;import sys;print(f'{sys.version} on {platform.platform()} {platform.uname()}')"
