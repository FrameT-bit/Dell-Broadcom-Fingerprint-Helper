#!/usr/bin/env bash
# Shared definitions and helpers.
#
# Portability notes
# -----------------
# * Debian/Ubuntu derivatives and Fedora-family hosts are both supported.
# * No distribution package is required for the firmware references any more:
#   they are always taken from a pinned Dell/Canonical reference package, so the
#   stack behaves identically on both families (see fw_ref_* below).
# * Every .deb is unpacked with `ar` + `tar`, never with dpkg, because Fedora
#   does not ship the dpkg toolset.

PROJECT_NAME="dell-broadcom-fingerprint-helper"
PROJECT_VERSION="0.2.0"
# Broadcom/Conexant ControlVault fingerprint readers. The whole "58xx" family is
# driven by the same TOD plugin, and the PID depends on the exact part/OEM SKU
# (Latitude 5420 reports 0a5c:5841 for its GF5288, other models report 0a5c:5843
# or 0a5c:5845), so every known ID is accepted instead of a single one.
SUPPORTED_USB_IDS=("0a5c:5841" "0a5c:5842" "0a5c:5843" "0a5c:5844" "0a5c:5845")

INSTALL_ROOT="/opt/${PROJECT_NAME}"
DROPIN_DIR="/etc/systemd/system/fprintd.service.d"
DROPIN_PATH="${DROPIN_DIR}/90-${PROJECT_NAME}.conf"
FW_REF_DIR="${INSTALL_ROOT}/share/fw"
# Where the unit override bind-mounts FW_REF_DIR. The directory has to exist on
# the host before the unit starts: ProtectSystem=strict leaves /var read-only in
# the unit's namespace, so systemd cannot create the mount point itself.
FW_MOUNT_POINT="/var/lib/fprint/fw"

FPRINTD_FILE="fprintd_1.90.9-1~ubuntu20.04.1_amd64.deb"
FPRINTD_URL="https://archive.ubuntu.com/ubuntu/pool/main/f/fprintd/${FPRINTD_FILE}"
FPRINTD_SHA256="b33a4b20612c5f29f3d0b0d74113430ca44598496d4c845cf34057af394caab3"

LIBFPRINT_FILE="libfprint-2-2_1.90.2+tod1-0ubuntu1~20.04.4_amd64.deb"
LIBFPRINT_URL="https://launchpad.net/ubuntu/+source/libfprint/1:1.90.2+tod1-0ubuntu1~20.04.4/+build/20415516/+files/${LIBFPRINT_FILE}"
LIBFPRINT_SHA256="ae65f246f2a4f4c7c0636837a7516a118e261185bfc5191b6d2c6ccc6b46a8b3"

TOD_FILE="libfprint-2-tod1_1.90.2+tod1-0ubuntu1~20.04.4_amd64.deb"
TOD_URL="https://launchpad.net/ubuntu/+source/libfprint/1:1.90.2+tod1-0ubuntu1~20.04.4/+build/20415516/+files/${TOD_FILE}"
TOD_SHA256="1d7223147652d05107d952d6c0e23e5b28a0025ac660a61b2199f7c556e76453"

OPENSSL_FILE="libssl1.1_1.1.1f-1ubuntu2.8_amd64.deb"
OPENSSL_URL="https://launchpad.net/~ubuntu-security/+archive/ubuntu/ppa/+build/22006918/+files/${OPENSSL_FILE}"
OPENSSL_SHA256="72fc71b96439fa82e95863aa2ab44ab3f200a0da26ca0917e30ac42812fcb5e8"

BROADCOM_FILE="libfprint-2-tod1-broadcom_5.8.012.0-0ubuntu1~oem2_amd64.deb"
BROADCOM_URL="http://dell.archive.canonical.com/updates/pool/public/libf/libfprint-2-tod1-broadcom/${BROADCOM_FILE}"
BROADCOM_SHA256="4c8e7f4127fb60650128208885c91448629f9ca1fedcd4f59f7a33d6e73aef06"

# Firmware reference packages. Only their /var/lib/fprint/fw trees are used:
# they are never installed and never taken from the host. install.sh verifies
# that the package really declares the selected release.
#
# The reference release MUST match the plugin build that is loaded: the firmware
# pack is parsed with offsets/section counts baked into the plugin, so a 5.8
# plugin reading a 5.15 pack fails with "Data read incorrect from file" ->
# "Cannot read contents of sensor-firmware file" and enrollment never starts.
# BROADCOM_FILE is the 5.8.012.0 build (the only one compatible with the pinned
# Ubuntu 20.04/libfprint 1.90 stack), so 5.8 is the matching default and is
# served from that very package instead of a second download.
BROADCOM_REF_BASE_URL="http://dell.archive.canonical.com/updates/pool/public/libf/libfprint-2-tod1-broadcom"
BROADCOM_REF_5_8_FILE="$BROADCOM_FILE"
BROADCOM_REF_5_8_SHA256="$BROADCOM_SHA256"
BROADCOM_REF_5_15_FILE="libfprint-2-tod1-broadcom_5.15.285-5.15.010.0-0ubuntu2~22.04.1~oem1_amd64.deb"
BROADCOM_REF_5_15_SHA256="98fa8afab8b97457329a74960f6a6404f32a1782bcdcaed96030ffa15badb962"
BROADCOM_REF_5_12_FILE="libfprint-2-tod1-broadcom_5.12.018-0ubuntu1~22.04.01_amd64.deb"
BROADCOM_REF_5_12_SHA256="c2b0822ce0a0b7b916c77259445b7fa06ea200f1204b5c62d01d3203db8b7e6a"

# FPRINT_FW_REF selects which reference release is fed to the plugin: 5.8
# (default, matches the bundled plugin), 5.12 or 5.15 (both built for the 22.04
# libfprint 1.94 stack and therefore only useful once the stack moves to it).
# The sensor firmware is only rewritten when the reference version differs from
# the version already on the sensor.
FPRINT_FW_REF="${FPRINT_FW_REF:-5.8}"

fw_ref_file() {
    case "$FPRINT_FW_REF" in
        5.8) printf '%s' "$BROADCOM_REF_5_8_FILE" ;;
        5.15) printf '%s' "$BROADCOM_REF_5_15_FILE" ;;
        5.12) printf '%s' "$BROADCOM_REF_5_12_FILE" ;;
        *) die "unsupported FPRINT_FW_REF: $FPRINT_FW_REF (expected 5.8, 5.12 or 5.15)" ;;
    esac
}

fw_ref_sha256() {
    case "$FPRINT_FW_REF" in
        5.8) printf '%s' "$BROADCOM_REF_5_8_SHA256" ;;
        5.15) printf '%s' "$BROADCOM_REF_5_15_SHA256" ;;
        5.12) printf '%s' "$BROADCOM_REF_5_12_SHA256" ;;
        *) die "unsupported FPRINT_FW_REF: $FPRINT_FW_REF (expected 5.8, 5.12 or 5.15)" ;;
    esac
}

fw_ref_url() {
    printf '%s/%s' "$BROADCOM_REF_BASE_URL" "$(fw_ref_file)"
}

log() {
    printf '[%s] %s\n' "$PROJECT_NAME" "$*"
}

warn() {
    printf '[%s] WARNING: %s\n' "$PROJECT_NAME" "$*" >&2
}

die() {
    printf '[%s] ERROR: %s\n' "$PROJECT_NAME" "$*" >&2
    exit 1
}

# TMPDIR is inherited from the caller and can point at a path this process
# cannot write to (a private mount, an unmounted tmpfs, a service environment).
# Fall back to /tmp so mktemp never fails on a stale TMPDIR.
tmp_base_dir() {
    local candidate=${TMPDIR:-/tmp}
    [[ -d $candidate && -w $candidate ]] || candidate=/tmp
    printf '%s\n' "$candidate"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

# Distribution family: debian, fedora, or unknown.
host_distro_id() {
    local id=""
    if [[ -r /etc/os-release ]]; then
        id=$(awk -F= '/^ID=/{gsub(/"/, "", $2); print $2; exit}' /etc/os-release)
    fi
    printf '%s' "$id"
}

host_distro_like() {
    local like=""
    if [[ -r /etc/os-release ]]; then
        like=$(awk -F= '/^ID_LIKE=/{gsub(/"/, "", $2); print $2; exit}' /etc/os-release)
    fi
    printf '%s' "$like"
}

host_distro_family() {
    local id like
    id=$(host_distro_id)
    like=$(host_distro_like)
    case "$id $like" in
        *ubuntu*|*debian*) printf 'debian' ;;
        *fedora*|*rhel*|*centos*) printf 'fedora' ;;
        *) printf 'unknown' ;;
    esac
}

host_arch() {
    case "$(uname -m)" in
        x86_64) printf 'amd64' ;;
        aarch64) printf 'arm64' ;;
        *) uname -m ;;
    esac
}

# Unpack a .deb without dpkg: control/data members are plain ar archives.
deb_extract() {
    local deb=$1
    local dest=$2
    local member=""

    mkdir -p -- "$dest"
    ( cd -- "$dest" && ar x -- "$deb" ) >/dev/null 2>&1 || \
        die "could not unpack $(basename "$deb") with ar"
    member=$(find "$dest" -maxdepth 1 -name 'data.tar.*' -print -quit)
    [[ -n $member ]] || die "no data.tar member inside $(basename "$deb")"
    tar -xf "$member" -C "$dest" || die "could not extract $(basename "$member")"
    rm -f -- "$dest"/data.tar.* "$dest"/control.tar.* "$dest"/debian-binary
}

# Version of an installed distribution package, empty when absent.
host_package_version() {
    local name=$1
    case "$(host_distro_family)" in
        debian) dpkg-query -W -f='${Version}' "$name" 2>/dev/null || true ;;
        fedora) rpm -q --qf '%{VERSION}-%{RELEASE}' "$name" 2>/dev/null || true ;;
        *) : ;;
    esac
}

pam_fingerprint_enabled() {
    case "$(host_distro_family)" in
        debian)
            grep -qE '^[[:space:]]*auth.*pam_fprintd\.so' /etc/pam.d/common-auth 2>/dev/null
            ;;
        fedora)
            grep -qE '^[[:space:]]*auth.*pam_fprintd\.so' \
                /etc/pam.d/system-auth /etc/pam.d/fingerprint-auth \
                /etc/authselect/system-auth 2>/dev/null || \
                authselect current 2>/dev/null | grep -q 'with-fingerprint'
            ;;
        *) return 1 ;;
    esac
}

pam_fingerprint_hint() {
    case "$(host_distro_family)" in
        debian) printf '%s' 'sudo pam-auth-update  (enable "Fingerprint authentication")' ;;
        fedora) printf '%s' 'sudo authselect enable-feature with-fingerprint && sudo authselect apply-changes' ;;
        *) printf '%s' 'enable pam_fprintd.so in the PAM stack of your distribution' ;;
    esac
}

download_verified() {
    local url=$1
    local output=$2
    local expected=$3
    local actual

    # The same package is legitimately requested twice when the firmware reference
    # is the plugin's own package, so a file already on disk with the right digest
    # is reused instead of downloaded again.
    if [[ -f $output ]]; then
        actual=$(sha256sum "$output" | awk '{print $1}')
        if [[ $actual == "$expected" ]]; then
            log "Reusing $(basename "$output") (SHA-256 already verified)"
            return 0
        fi
    fi

    log "Downloading $(basename "$output")"
    curl --fail --location --retry 3 --connect-timeout 20 --http1.1 \
        --show-error --output "$output" "$url"
    actual=$(sha256sum "$output" | awk '{print $1}')
    [[ $actual == "$expected" ]] || die "invalid SHA-256 for $(basename "$output"): $actual"
    log "SHA-256 verified: $(basename "$output")"
}

supported_usb_ids() {
    printf '%s' "${SUPPORTED_USB_IDS[*]}"
}

detected_usb_ids() {
    local id
    for id in "${SUPPORTED_USB_IDS[@]}"; do
        lsusb -d "$id" 2>/dev/null | grep -qi "$id" && printf '%s\n' "$id"
    done
}

is_supported_device_present() {
    [[ -n $(detected_usb_ids) ]]
}
