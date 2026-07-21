#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

[[ $EUID -eq 0 ]] || die "uninstall must run as root (use sudo)"

removed=false
if [[ -f $DROPIN_PATH ]]; then
    rm -f -- "$DROPIN_PATH"
    removed=true
fi

if [[ -d $INSTALL_ROOT ]]; then
    rm -rf -- "$INSTALL_ROOT"
    removed=true
fi

systemctl daemon-reload
systemctl restart fprintd.service || warn "the distribution fprintd service could not be restarted"

if $removed; then
    log "Helper removed; the distribution fprintd service was restored"
else
    log "The helper was not installed"
fi
log "Enrolled fingerprints and PAM configuration were preserved"
