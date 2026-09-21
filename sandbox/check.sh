#!/usr/bin/env bash
set -Eeuo pipefail

stack=/opt/fingerprint-stack
plugin="$stack/lib/libfprint-2/tod-1/libfprint-2-tod-1-broadcom.so"

[[ -x $stack/bin/fprintd ]] || {
    printf 'Missing private fprintd binary.\n' >&2
    exit 1
}
[[ -f $plugin ]] || {
    printf 'Missing private Broadcom plugin.\n' >&2
    exit 1
}

for binary in "$stack/bin/fprintd" "$plugin"; do
    result=$(ldd "$binary" 2>&1 || true)
    if grep -q 'not found' <<<"$result"; then
        printf '%s\n' "$result" >&2
        exit 1
    fi
done

printf 'Bubblewrap stack check passed.\n'
sed -n '1,6p' "$stack/share/manifest.txt"
