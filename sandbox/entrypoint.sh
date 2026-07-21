#!/usr/bin/env bash
set -Eeuo pipefail

mode=${1:-smoke}
finger=${2:-right-index-finger}
daemon_pid=""
bus_pid=""

cleanup() {
    [[ -z $daemon_pid ]] || kill "$daemon_pid" 2>/dev/null || true
    [[ -z $bus_pid ]] || kill "$bus_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mkdir -p /run/private-dbus /tmp/home
dbus-daemon --config-file=/project/sandbox/dbus.conf \
    --fork --print-pid=1 > /run/private-dbus/bus.pid
bus_pid=$(sed -n '1p' /run/private-dbus/bus.pid)

/opt/fingerprint-stack/bin/fprintd > /run/fprintd.log 2>&1 &
daemon_pid=$!

ready=false
for _ in {1..50}; do
    if gdbus call --system --dest net.reactivated.Fprint \
        --object-path /net/reactivated/Fprint/Manager \
        --method net.reactivated.Fprint.Manager.GetDevices \
        > /run/devices.txt 2>/dev/null; then
        ready=true
        break
    fi
    sleep 0.1
done

if ! $ready; then
    printf 'The private fprintd daemon did not become ready.\n' >&2
    sed -n '1,160p' /run/fprintd.log >&2
    exit 1
fi

case $mode in
    smoke)
        printf 'Private D-Bus device response: '
        sed -n '1p' /run/devices.txt
        printf '\nPrivate daemon log:\n'
        sed -n '1,160p' /run/fprintd.log
        ;;
    list)
        fprintd-list root
        ;;
    enroll)
        printf 'Enrollment changes the fingerprint data stored by the sensor.\n'
        fprintd-enroll -f "$finger" root
        ;;
    verify)
        fprintd-verify -f "$finger" root
        ;;
    shell)
        printf 'Private fprintd is running. State is discarded when this shell exits.\n'
        exec bash --noprofile --norc
        ;;
    *)
        printf 'Unknown sandbox action: %s\n' "$mode" >&2
        exit 2
        ;;
esac
