#!/usr/bin/env bash
# Portability guards: the project must stay distribution-agnostic.
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib/common.sh
source "$ROOT_DIR/lib/common.sh"

failures=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

# Debian-only tooling may only appear behind the family switch in lib/common.sh.
offenders=$(grep -nE '\b(dpkg-query|dpkg-deb|dpkg -i|apt-get|apt install)\b' \
    "$ROOT_DIR"/*.sh "$ROOT_DIR"/sandbox/*.sh "$ROOT_DIR"/tests/*.sh 2>/dev/null \
    | grep -v 'lib/common.sh' | grep -v 'tests/distro-portability.sh' || true)
[[ -z $offenders ]] || fail "Debian-only tooling outside lib/common.sh: $offenders"

[[ $(host_arch) == amd64 ]] || fail "host_arch did not report amd64 on this amd64 host"

case "$(host_distro_family)" in
    debian|fedora) ;;
    *) fail "host_distro_family returned '$(host_distro_family)'" ;;
esac

for reference in 5.15 5.12; do
    file=$(FPRINT_FW_REF=$reference fw_ref_file)
    sha=$(FPRINT_FW_REF=$reference fw_ref_sha256)
    [[ $file == libfprint-2-tod1-broadcom_*_amd64.deb ]] || \
        fail "reference $reference resolves to '$file'"
    ((${#sha} == 64)) || fail "reference $reference has no pinned SHA-256"
done

if (FPRINT_FW_REF=9.9 fw_ref_file) >/dev/null 2>&1; then
    fail "an unsupported firmware reference was accepted"
fi

grep -q 'share/fw' "$ROOT_DIR/sandbox.sh" || \
    fail "sandbox.sh does not mount the staged firmware references"
if grep -q -- '--ro-bind /var/lib/fprint/fw /var/lib/fprint/fw' "$ROOT_DIR/sandbox.sh"; then
    fail "sandbox.sh still depends on host firmware references"
fi

grep -qE '^BindReadOnlyPaths=.*share/fw:/var/lib/fprint/fw$' \
    "$ROOT_DIR/systemd/override.conf" || \
    fail "the unit override does not bind the staged firmware references"

grep -qE '^MemoryDenyWriteExecute=false$' "$ROOT_DIR/systemd/override.conf" || \
    fail "the unit override does not relax MemoryDenyWriteExecute for the legacy plugin"

grep -qE '^SystemCallFilter=$' "$ROOT_DIR/systemd/override.conf" || \
    fail "the unit override does not reset SystemCallFilter for the legacy plugin"

if ((failures)); then
    printf 'Portability tests failed: %d\n' "$failures" >&2
    exit 1
fi

printf 'Portability tests completed.\n'
