#!/usr/bin/env bash
# Guard for the unit override: a bind mount whose target does not exist on the
# host aborts the daemon start with status=226/NAMESPACE, because
# ProtectSystem=strict leaves /var read-only inside the unit namespace and
# systemd therefore cannot create the mount point itself.
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

override_path="$ROOT_DIR/systemd/override.conf"
install_path="$ROOT_DIR/install.sh"
uninstall_path="$ROOT_DIR/uninstall.sh"
failures=0

fail() {
    printf 'bind mount guard: %s\n' "$*" >&2
    failures=$((failures + 1))
}

for required in "$override_path" "$install_path" "$uninstall_path"; do
    [[ -f $required ]] || {
        printf 'bind mount guard: %s is missing\n' "$required" >&2
        exit 1
    }
done

# Installed paths are referenced through lib/common.sh variables, so render them
# before looking for the literal mount point.
render() {
    sed -e "s|\$FW_MOUNT_POINT|$FW_MOUNT_POINT|g" \
        -e "s|\$FW_REF_DIR|$FW_REF_DIR|g" \
        -e "s|\$INSTALL_ROOT|$INSTALL_ROOT|g" "$1"
}

sources=()
targets=()
while IFS= read -r line; do
    [[ $line == Bind*Paths=* ]] || continue
    value=${line#*=}
    value=${value#-}
    if [[ $value != *:* ]]; then
        fail "$line does not use SOURCE:TARGET form"
        continue
    fi
    sources+=("${value%%:*}")
    targets+=("${value##*:}")
done <"$override_path"

(( ${#targets[@]} > 0 )) || {
    printf 'bind mount guard: the override declares no bind mounts; the firmware references are missing\n' >&2
    exit 1
}

create_lines=$(render "$install_path" | grep -E '^[[:space:]]*install -d' || true)
remove_lines=$(render "$uninstall_path" | grep -E '^[[:space:]]*rmdir' || true)

for index in "${!targets[@]}"; do
    source_path=${sources[index]}
    target_path=${targets[index]}

    [[ $source_path == "$INSTALL_ROOT"/* ]] ||
        fail "$source_path is outside the installed helper ($INSTALL_ROOT)"

    [[ $source_path == "$FW_REF_DIR" ]] ||
        fail "$source_path is not the staged firmware reference directory ($FW_REF_DIR)"

    [[ $target_path == "$FW_MOUNT_POINT" ]] ||
        fail "$target_path is not the documented firmware mount point ($FW_MOUNT_POINT)"

    grep -qF -- "$target_path" <<<"$create_lines" ||
        fail "install.sh does not create the mount point $target_path before the daemon starts"

    grep -qF -- "$target_path" <<<"$remove_lines" ||
        fail "uninstall.sh does not clean up the mount point $target_path"
done

grep -qF -- "ExecStart=${INSTALL_ROOT}/bin/fprintd" "$override_path" ||
    fail "ExecStart does not point at the installed daemon"

grep -qF -- "Environment=FP_TOD_DRIVERS_DIR=${INSTALL_ROOT}/lib/libfprint-2/tod-1" "$override_path" ||
    fail "FP_TOD_DRIVERS_DIR does not point at the installed plugin directory"

grep -qF -- "Environment=LD_LIBRARY_PATH=${INSTALL_ROOT}/lib" "$override_path" ||
    fail "LD_LIBRARY_PATH does not point at the installed libraries"

if (( failures > 0 )); then
    printf '%d bind mount check(s) failed.\n' "$failures" >&2
    exit 1
fi

printf 'Unit bind mount checks passed.\n'
