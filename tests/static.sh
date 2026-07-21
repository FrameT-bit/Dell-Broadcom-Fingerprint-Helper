#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

scripts=(
    "$ROOT_DIR/install.sh"
    "$ROOT_DIR/uninstall.sh"
    "$ROOT_DIR/diagnose.sh"
    "$ROOT_DIR/sandbox.sh"
    "$ROOT_DIR/sandbox/entrypoint.sh"
    "$ROOT_DIR/sandbox/check.sh"
    "$ROOT_DIR/lib/common.sh"
    "$ROOT_DIR/tests/download-smoke.sh"
)

for script in "${scripts[@]}"; do
    bash -n "$script"
done

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "${scripts[@]}"
else
    printf 'shellcheck is not installed; bash -n validation completed.\n'
fi

printf 'Static tests completed.\n'
