#!/usr/bin/env bash
set -eu
set -o pipefail

if [ -z "${GITHUB_ENV:-}" ]; then
  uv run cred_tool "ENV.${PROJECT_NAME}" "${PROJECT_NAME}" build | jq -r '. | to_entries[] | [.key,.value] | @tsv' | tr '\t' '=' | sed 's/=\(.*\)/="\1"/'
fi
