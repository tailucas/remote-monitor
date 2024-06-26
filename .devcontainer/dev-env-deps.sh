#!/usr/bin/env bash
set -eu
set -o pipefail

if ! poetry --version; then
  curl -sSL https://install.python-poetry.org | POETRY_HOME=~/.local python3 -
fi

if ! poetry show --tree; then
  poetry install --no-interaction
  poetry show --tree
fi
