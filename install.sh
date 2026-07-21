#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

dry_run=false
force=false
stage_dir=""
work_dir=""
new_root=""

usage() {
    cat <<EOF
Usage: sudo ./install.sh [--force]
     ./install.sh --dry-run [--force]
     ./install.sh --stage DIRECTORY [--force]

  --dry-run         download and validate without changing the system
  --stage DIRECTORY build the private stack in DIRECTORY without installing it
  --force           skip the USB model and distribution checks
EOF
}

cleanup() {
    [[ -z $work_dir || ! -d $work_dir ]] || rm -rf -- "$work_dir"
    [[ -z $new_root || ! -d $new_root ]] || rm -rf -- "$new_root"
}
trap cleanup EXIT

while (($#)); do
    case $1 in
        --dry-run) dry_run=true ;;
        --stage)
            shift
            (($#)) || die "--stage requires a directory"
            stage_dir=$1
            ;;
        --force) force=true ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown option: $1" ;;
    esac
    shift
done

if $dry_run && [[ -n $stage_dir ]]; then
    die "--dry-run and --stage cannot be used together"
fi

for command_name in awk cp curl dpkg dpkg-deb dpkg-query find grep install ldd lsusb sha256sum systemctl; do
    require_command "$command_name"
done

[[ $(dpkg --print-architecture) == amd64 ]] || die "only the amd64 architecture is supported"

if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
else
    die "could not identify the distribution"
fi

if ! $force; then
    [[ ${ID:-} == ubuntu || ${ID_LIKE:-} == *ubuntu* ]] || \
        die "this release supports Ubuntu derivatives only; use --force at your own risk"
    is_supported_device_present || \
        die "USB reader $SUPPORTED_USB_ID was not found; use --force only for known-compatible hardware"
fi

if ! $dry_run && [[ -z $stage_dir && $EUID -ne 0 ]]; then
    die "installation must run as root (use sudo)"
fi

if ! $dry_run && [[ -z $stage_dir ]]; then
    firmware_package_version=$(dpkg-query -W -f='${Version}' \
        libfprint-2-tod1-broadcom 2>/dev/null || true)
    [[ -n $firmware_package_version ]] || \
        die "the current Ubuntu Broadcom package is required"
    [[ $firmware_package_version != 5.8.012.0-* ]] || \
        die "the installed Broadcom firmware package is legacy and is not safe for this workflow"
    [[ -r /var/lib/fprint/fw/bcm_cv_current_version.txt ]] || \
        die "current Ubuntu Broadcom firmware references are missing; install the distribution Broadcom package first"
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/${PROJECT_NAME}.XXXXXX")
packages_dir="$work_dir/packages"
extract_dir="$work_dir/extracted"
mkdir -p "$packages_dir" "$extract_dir"

download_verified "$FPRINTD_URL" "$packages_dir/$FPRINTD_FILE" "$FPRINTD_SHA256"
download_verified "$LIBFPRINT_URL" "$packages_dir/$LIBFPRINT_FILE" "$LIBFPRINT_SHA256"
download_verified "$TOD_URL" "$packages_dir/$TOD_FILE" "$TOD_SHA256"
download_verified "$OPENSSL_URL" "$packages_dir/$OPENSSL_FILE" "$OPENSSL_SHA256"
download_verified "$BROADCOM_URL" "$packages_dir/$BROADCOM_FILE" "$BROADCOM_SHA256"

for package_file in "$packages_dir"/*.deb; do
    package_name=$(basename "$package_file" .deb)
    dpkg-deb -x "$package_file" "$extract_dir/$package_name"
done

fprintd_binary=$(find "$extract_dir" -type f -path '*/usr/libexec/fprintd' -print -quit)
libfprint_library=$(find "$extract_dir" -type f -path '*/usr/lib/x86_64-linux-gnu/libfprint-2.so.2.*' -print -quit)
tod_library=$(find "$extract_dir" -type f -path '*/usr/lib/x86_64-linux-gnu/libfprint-2-tod.so.1*' -print -quit)
ssl_library=$(find "$extract_dir" -type f -path '*/usr/lib/x86_64-linux-gnu/libssl.so.1.1' -print -quit)
crypto_library=$(find "$extract_dir" -type f -path '*/usr/lib/x86_64-linux-gnu/libcrypto.so.1.1' -print -quit)
broadcom_plugin=$(find "$extract_dir" -type f -name 'libfprint-2-tod-1-broadcom.so' -print -quit)

[[ -n $fprintd_binary && -n $libfprint_library && -n $tod_library ]] || \
    die "core components were not found in the packages"
[[ -n $ssl_library && -n $crypto_library && -n $broadcom_plugin ]] || \
    die "OpenSSL 1.1 or the Broadcom plugin was not found in the packages"

if [[ -n $stage_dir ]]; then
    [[ ! -e $stage_dir ]] || die "staging destination already exists: $stage_dir"
    mkdir -p -- "$stage_dir"
    new_root=$(cd -- "$stage_dir" && pwd)
elif $dry_run; then
    new_root="$work_dir/staged"
else
    new_root=$(mktemp -d "/opt/.${PROJECT_NAME}.new.XXXXXX")
fi

install -d -m 0755 "$new_root/bin" "$new_root/lib/libfprint-2/tod-1" \
    "$new_root/share"
install -m 0755 "$fprintd_binary" "$new_root/bin/fprintd"

for package_tree in "$extract_dir"/*; do
    if [[ -d $package_tree/usr/lib/x86_64-linux-gnu ]]; then
        cp -a "$package_tree/usr/lib/x86_64-linux-gnu/." "$new_root/lib/"
    fi
done

install -m 0644 "$broadcom_plugin" \
    "$new_root/lib/libfprint-2/tod-1/libfprint-2-tod-1-broadcom.so"

cat > "$new_root/share/manifest.txt" <<EOF
$PROJECT_NAME $PROJECT_VERSION
$FPRINTD_SHA256  $FPRINTD_FILE
$LIBFPRINT_SHA256  $LIBFPRINT_FILE
$TOD_SHA256  $TOD_FILE
$OPENSSL_SHA256  $OPENSSL_FILE
$BROADCOM_SHA256  $BROADCOM_FILE
EOF

ldd_output=$(LD_LIBRARY_PATH="$new_root/lib" ldd "$new_root/bin/fprintd" 2>&1 || true)
if grep -q 'not found' <<<"$ldd_output"; then
    printf '%s\n' "$ldd_output" >&2
    die "the compatibility environment has missing libraries"
fi

plugin_ldd=$(LD_LIBRARY_PATH="$new_root/lib" ldd \
    "$new_root/lib/libfprint-2/tod-1/libfprint-2-tod-1-broadcom.so" 2>&1 || true)
if grep -q 'not found' <<<"$plugin_ldd"; then
    printf '%s\n' "$plugin_ldd" >&2
    die "the Broadcom plugin has missing libraries"
fi

if $dry_run; then
    log "Dry run complete: packages, checksums, extraction, and dependencies are valid."
    log "No system changes were made."
    exit 0
fi

if [[ -n $stage_dir ]]; then
    log "Compatibility stack staged in $stage_dir"
    new_root=""
    exit 0
fi

if [[ -d $DROPIN_DIR ]]; then
    for dropin in "$DROPIN_DIR"/*.conf; do
        [[ -e $dropin || $dropin == "$DROPIN_PATH" ]] || continue
        [[ $dropin == "$DROPIN_PATH" ]] && continue
        if grep -q '^[[:space:]]*ExecStart=' "$dropin"; then
            die "another ExecStart override exists in $dropin; disable it before installation"
        fi
    done
fi

backup_root=""
if [[ -e $INSTALL_ROOT ]]; then
    backup_root="${INSTALL_ROOT}.backup.$(date +%Y%m%d%H%M%S)"
    mv -- "$INSTALL_ROOT" "$backup_root"
fi
mv -- "$new_root" "$INSTALL_ROOT"
new_root=""

install -d -m 0755 "$DROPIN_DIR"
install -m 0644 "$SCRIPT_DIR/systemd/override.conf" "$DROPIN_PATH"
systemctl daemon-reload

if ! systemctl restart fprintd.service || ! systemctl is-active --quiet fprintd.service; then
    warn "the compatibility daemon did not start; rolling back"
    rm -f -- "$DROPIN_PATH"
    rm -rf -- "$INSTALL_ROOT"
    if [[ -n $backup_root && -d $backup_root ]]; then
        mv -- "$backup_root" "$INSTALL_ROOT"
    fi
    systemctl daemon-reload
    systemctl restart fprintd.service || true
    die "installation rolled back; run ./diagnose.sh for diagnostics"
fi

[[ -z $backup_root || ! -d $backup_root ]] || rm -rf -- "$backup_root"

if ! grep -qE '^[[:space:]]*auth.*pam_fprintd\.so' /etc/pam.d/common-auth 2>/dev/null; then
    warn "PAM fingerprint authentication is not enabled. Run: sudo pam-auth-update"
    warn "Select 'Fingerprint authentication'."
fi

log "Installation complete. Enroll with: fprintd-enroll -f right-index-finger"
log "Then validate with: fprintd-verify"
