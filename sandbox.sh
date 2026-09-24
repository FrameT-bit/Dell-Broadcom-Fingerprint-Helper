#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

action=${1:-check}
finger=${2:-right-index-finger}
sandbox_dir=""

usage() {
    cat <<'EOF'
Usage: ./sandbox.sh [check|smoke|list|enroll|verify|shell] [finger]

The default check validates the stack inside Bubblewrap without USB access.
Other actions access physical hardware and require explicit confirmation.
EOF
}

cleanup() {
    [[ -z $sandbox_dir || ! -d $sandbox_dir ]] || rm -rf -- "$sandbox_dir"
}
trap cleanup EXIT INT TERM

case $action in
    check|smoke|list|enroll|verify|shell) ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown sandbox action: $action" ;;
esac

for command_name in ar bwrap lsusb tar; do
    require_command "$command_name"
done

is_supported_device_present || die "no supported USB fingerprint reader found (looked for: $(supported_usb_ids))"
[[ -d /dev/bus/usb ]] || die "/dev/bus/usb is not available"

sandbox_dir=$(mktemp -d "$(tmp_base_dir)/${PROJECT_NAME}-sandbox.XXXXXX")
stack_dir="$sandbox_dir/stack"
log "Building a verified, temporary compatibility stack"
"$SCRIPT_DIR/install.sh" --stage "$stack_dir"

if [[ $action == check ]]; then
    log "Starting a no-hardware Bubblewrap check"
    bwrap \
        --die-with-parent \
        --new-session \
        --unshare-user --uid 0 --gid 0 \
        --unshare-pid --unshare-ipc --unshare-uts --unshare-cgroup-try \
        --unshare-net \
        --ro-bind /usr /usr \
        --symlink usr/bin /bin \
        --symlink usr/sbin /sbin \
        --symlink usr/lib /lib \
        --symlink usr/lib64 /lib64 \
        --ro-bind /etc /etc \
        --proc /proc \
        --dev /dev \
        --tmpfs /tmp \
        --ro-bind "$stack_dir" /opt/fingerprint-stack \
        --ro-bind "$SCRIPT_DIR" /project \
        --setenv HOME /tmp \
        --setenv LD_LIBRARY_PATH /opt/fingerprint-stack/lib \
        --setenv FP_TOD_DRIVERS_DIR /opt/fingerprint-stack/lib/libfprint-2/tod-1 \
        -- /project/sandbox/check.sh
    log "Sandbox closed; no USB device was exposed"
    exit 0
fi

for command_name in dbus-daemon fprintd-enroll fprintd-list fprintd-verify gdbus sudo; do
    require_command "$command_name"
done

fw_ref_version=$(awk -F': ' '/^version:/{print $2; exit}' \
    "$stack_dir/share/fw/bcm_cv_current_version.txt" 2>/dev/null || true)
[[ -n $fw_ref_version ]] || die "the staged stack carries no firmware references"
[[ $fw_ref_version == "$FPRINT_FW_REF".* ]] || die \
    "the staged stack carries $fw_ref_version, which is not the selected FPRINT_FW_REF=$FPRINT_FW_REF"

printf '%s\n' \
    'WARNING: the proprietary plugin can update the physical sensor firmware' \
    "when the sensor version differs from the reference release $fw_ref_version" \
    '(select another reference with FPRINT_FW_REF=5.12).' \
    'Bubblewrap isolates host files and packages, but it cannot undo USB writes.'
read -r -p 'Type YES to allow hardware access: ' confirmation
[[ $confirmation == YES ]] || die "hardware test cancelled"

raw_udev_args=()
[[ -d /run/udev ]] && raw_udev_args=(--ro-bind /run/udev /run/udev)

log "Starting the isolated test environment"
sudo -- bwrap \
    --die-with-parent \
    --new-session \
    --unshare-user --uid 0 --gid 0 \
    --unshare-pid --unshare-ipc --unshare-uts --unshare-cgroup-try \
    --unshare-net \
    --ro-bind /usr /usr \
    --symlink usr/bin /bin \
    --symlink usr/sbin /sbin \
    --symlink usr/lib /lib \
    --symlink usr/lib64 /lib64 \
    --ro-bind /etc /etc \
    --ro-bind /sys /sys \
    --proc /proc \
    --dev /dev \
    --dir /dev/bus \
    --dir /dev/bus/usb \
    --dev-bind /dev/bus/usb /dev/bus/usb \
    --tmpfs /tmp \
    --dir /run \
    "${raw_udev_args[@]}" \
    --dir /var \
    --dir /var/lib \
    --tmpfs /var/lib/fprint \
    --ro-bind "$stack_dir/share/fw" /var/lib/fprint/fw \
    --ro-bind "$stack_dir" /opt/fingerprint-stack \
    --ro-bind "$SCRIPT_DIR" /project \
    --setenv HOME /tmp/home \
    --setenv DBUS_SYSTEM_BUS_ADDRESS unix:path=/run/private-dbus/system_bus_socket \
    --setenv LD_LIBRARY_PATH /opt/fingerprint-stack/lib \
    --setenv FP_TOD_DRIVERS_DIR /opt/fingerprint-stack/lib/libfprint-2/tod-1 \
    -- /project/sandbox/entrypoint.sh "$action" "$finger"

log "Sandbox closed; its filesystem state was discarded"
