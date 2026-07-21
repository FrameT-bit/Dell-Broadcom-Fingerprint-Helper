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
    lsusb -d "$SUPPORTED_USB_ID" 2>/dev/null || printf 'USB %s not found\n' "$SUPPORTED_USB_ID"
else
    printf 'lsusb is not installed\n'
fi

section "Distribution packages"
for package_name in fprintd libfprint-2-2 libfprint-2-tod1 libpam-fprintd; do
    version=$(dpkg-query -W -f='${Version}' "$package_name" 2>/dev/null || true)
    printf '%-20s %s\n' "$package_name" "${version:-not installed}"
done

section "Helper"
if [[ -r $INSTALL_ROOT/share/manifest.txt ]]; then
    sed -n '1,10p' "$INSTALL_ROOT/share/manifest.txt"
    printf '\nMain files:\n'
    sha256sum "$INSTALL_ROOT/bin/fprintd" \
        "$INSTALL_ROOT/lib/libfprint-2/tod-1/libfprint-2-tod-1-broadcom.so" 2>/dev/null || true
else
    printf 'Not installed in %s\n' "$INSTALL_ROOT"
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
