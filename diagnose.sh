#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

section() {
    printf '\n== %s ==\n' "$1"
}

section "System"
if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    printf 'Distribution: %s\n' "${PRETTY_NAME:-unknown}"
fi
printf 'Kernel: %s\n' "$(uname -r)"
printf 'Architecture: %s\n' "$(uname -m)"

section "Compatible reader"
if command -v lsusb >/dev/null 2>&1; then
    detected=$(detected_usb_ids)
    if [[ -n $detected ]]; then
        printf 'found: %s\n' "${detected//$'\n'/ }"
    else
        printf 'no supported reader found (looked for: %s)\n' "$(supported_usb_ids)"
    fi
else
    printf 'lsusb is not installed\n'
fi

section "Distribution packages"
case "$(host_distro_family)" in
    debian) package_names=(fprintd libfprint-2-2 libfprint-2-tod1 libpam-fprintd) ;;
    fedora) package_names=(fprintd libfprint pcsc-lite) ;;
    *) package_names=() ;;
esac
if ((${#package_names[@]})); then
    for package_name in "${package_names[@]}"; do
        version=$(host_package_version "$package_name")
        printf '%-20s %s\n' "$package_name" "${version:-not installed}"
    done
else
    printf 'Unrecognised distribution family; package inventory skipped\n'
fi

section "Fingerprint PAM stack"
if pam_fingerprint_enabled; then
    printf 'pam_fprintd is referenced by the authentication stack\n'
else
    printf 'pam_fprintd is not referenced by the authentication stack\n'
    printf 'Enable it with: %s\n' "$(pam_fingerprint_hint)"
fi

if command -v getenforce >/dev/null 2>&1; then
    section "SELinux"
    printf 'Mode: %s\n' "$(getenforce)"
    policy_modules=$(semodule -l 2>/dev/null | grep -c '^fprintd' || true)
    printf 'fprintd policy modules: %s\n' "${policy_modules:-unavailable without root}"
fi

section "Helper"
if [[ -r $INSTALL_ROOT/share/manifest.txt ]]; then
    sed -n '1,10p' "$INSTALL_ROOT/share/manifest.txt"
    printf '\nMain files:\n'
    sha256sum "$INSTALL_ROOT/bin/fprintd" \
        "$INSTALL_ROOT/lib/libfprint-2/tod-1/libfprint-2-tod-1-broadcom.so" 2>/dev/null || true
else
    printf 'Not installed in %s\n' "$INSTALL_ROOT"
fi

section "Firmware references"
if [[ -r $FW_REF_DIR/bcm_cv_current_version.txt ]]; then
    awk -F': ' '/^version:|^SBI_VERSION:/{printf "%-14s %s\n", $1, $2}' \
        "$FW_REF_DIR/bcm_cv_current_version.txt"
    printf 'Reference files: %s\n' "$(find "$FW_REF_DIR" -maxdepth 1 -type f | wc -l)"
else
    printf 'Not present in %s\n' "$FW_REF_DIR"
fi

section "fprintd service"
systemctl show fprintd.service \
    --property=LoadState,ActiveState,SubState,ExecStart,Environment --no-pager 2>/dev/null || true
printf '\nOverrides containing ExecStart:\n'
if [[ -d $DROPIN_DIR ]]; then
    grep -H '^[[:space:]]*ExecStart=' "$DROPIN_DIR"/*.conf 2>/dev/null || printf 'none\n'
else
    printf 'none\n'
fi
printf '\nFirmware references mounted by overrides:\n'
if [[ -d $DROPIN_DIR ]]; then
    grep -H '^[[:space:]]*BindReadOnlyPaths=' "$DROPIN_DIR"/*.conf 2>/dev/null || printf 'none\n'
else
    printf 'none\n'
fi
printf '\nHost /var/lib/fprint/fw: %s\n' \
    "$([[ -e /var/lib/fprint/fw ]] && printf 'present' || printf 'absent (the unit override bind-mounts it from the stack)')"

section "Current account fingerprints"
if command -v fprintd-list >/dev/null 2>&1; then
    current_user=$(id -un)
    fprintd-list "$current_user" 2>&1 | sed "s/${current_user}/USUARIO/g" || true
else
    printf 'fprintd-list was not found\n'
fi

section "Recent relevant events"
journalctl -u fprintd.service -n 120 --no-pager --output=cat 2>/dev/null \
    | grep -Ei 'error|fail|disconnect|status|enroll|verify|device|usb|tod|broadcom' \
    | sed -E 's#/home/[^ /]+#/home/USER#g' \
    | tail -n 40 || true

printf '\nThe report removes account and host names and omits IP, serial, and service-tag data. Review it before publishing.\n'
