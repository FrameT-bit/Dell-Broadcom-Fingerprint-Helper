#!/usr/bin/env bash

PROJECT_NAME="dell-broadcom-fingerprint-helper"
PROJECT_VERSION="0.1.0"
SUPPORTED_USB_ID="0a5c:5843"

INSTALL_ROOT="/opt/${PROJECT_NAME}"
DROPIN_DIR="/etc/systemd/system/fprintd.service.d"
DROPIN_PATH="${DROPIN_DIR}/90-${PROJECT_NAME}.conf"

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

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

download_verified() {
    local url=$1
    local output=$2
    local expected=$3
    local actual

    log "Downloading $(basename "$output")"
    curl --fail --location --retry 3 --connect-timeout 20 --http1.1 \
        --show-error --output "$output" "$url"
    actual=$(sha256sum "$output" | awk '{print $1}')
    [[ $actual == "$expected" ]] || die "invalid SHA-256 for $(basename "$output"): $actual"
    log "SHA-256 verified: $(basename "$output")"
}

is_supported_device_present() {
    lsusb -d "$SUPPORTED_USB_ID" 2>/dev/null | grep -qi "$SUPPORTED_USB_ID"
}
