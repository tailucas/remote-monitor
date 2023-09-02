#!/usr/bin/env bash
set -u

# system updates
if ! poetry --version; then
  curl -sSL https://install.python-poetry.org | python - || cat /opt/app/poetry-installer-error-*
else
  poetry self update
fi
poetry install
poetry show
