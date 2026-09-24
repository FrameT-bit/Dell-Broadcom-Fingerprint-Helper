# Technical research

## Symptom

On the Latitude 5420 reader with USB ID `0a5c:5843` (the unit this was diagnosed on
reports `0a5c:5841`; the ControlVault 58xx family spans `0a5c:5841`-`0a5c:5845`),
current `fprintd` and
`libfprint` versions detected the device and accepted roughly ten enrollment
stages. Completion then returned `enroll-disconnected` or
`enroll-unknown-error`, and no fingerprint was saved.

## Tested combinations

| Daemon and libfprint | Plugin | Result |
|---|---|---|
| Current Ubuntu stack | Distribution plugin | Enrollment failed at completion |
| Current Ubuntu stack | Broadcom 5.8.012.0 | Enrollment failed at completion |
| Complete Ubuntu 20.04-era stack | Broadcom 5.8.012.0 | Enrollment and PAM authentication worked |

The result points to an ABI or behavioral incompatibility between the legacy
plugin and the current userspace stack. Replacing only the plugin is therefore
not sufficient.

## Reproduced working set

```text
fprintd                 1.90.9-1~ubuntu20.04.1
libfprint-2-2           1:1.90.2+tod1-0ubuntu1~20.04.4
libfprint-2-tod1        1:1.90.2+tod1-0ubuntu1~20.04.4
libssl1.1               1.1.1f-1ubuntu2.8
libfprint Broadcom TOD  5.8.012.0-0ubuntu1~oem2
```

The result was reproduced on amd64 Ubuntu with the target Latitude 5420 reader.
No user, host, serial number, service tag, or network information is retained in
this project.

## Portability to Fedora-family hosts

The stack itself is distribution independent: it is a private directory holding
`fprintd` 1.90.9, `libfprint`/TOD 1.90.2, OpenSSL 1.1, and the Broadcom plugin,
pointed at each other with `LD_LIBRARY_PATH` and `FP_TOD_DRIVERS_DIR`. Verified
on Fedora 44 with the stack extracted from the pinned `.deb` files:

| Check | Result |
|---|---|
| Extraction with `ar` + `tar` (no dpkg) | worked |
| `ldd` of `bin/fprintd` with `LD_LIBRARY_PATH` | every dependency resolved |
| `ldd` of the Broadcom plugin | every dependency resolved |
| `fprintd` 1.90.9 executed inside Bubblewrap | 0.2.0 stack check passed |
| Firmware reference files from the reference package | mounted read-only at `/var/lib/fprint/fw` |

Fedora-specific differences handled by the port:

- package inventory uses `rpm` instead of `dpkg-query`;
- the hardened Fedora unit (`MemoryDenyWriteExecute=true`, `SystemCallFilter`
  allowlist) is relaxed for the compatibility daemon, matching the unhardened
  Ubuntu unit the plugin was validated against;
- `StateDirectory=fprint` and the USB device allowlist of the Fedora unit are
  preserved, so prints are stored in `/var/lib/fprint` as usual;
- no udev rule is installed: `strings` shows that the legacy `libfprint` never
  reads `LIBFPRINT_DRIVER`, so driver selection is by USB ID only;
- SELinux has no `fprintd` policy module on Fedora, which leaves the
  compatibility daemon unconfined instead of blocked.

Enrollment and PAM authentication on Fedora are expected to behave exactly as on
Ubuntu because both use the same binaries; the hardware confirmation must still
be repeated per machine.

## Isolation model

Installing legacy libraries as system packages could downgrade dependencies
used by unrelated applications. This helper extracts the stack into a private
directory and points only its `fprintd` process at those libraries.

The Bubblewrap workflow goes further: its private stack, D-Bus, runtime state,
and fingerprint state exist only in a temporary mount namespace. Current Ubuntu
firmware reference files are mounted read-only. The physical USB reader remains
accessible because hardware discovery is the purpose of the test, so direct
device changes cannot be sandboxed or rolled back by Bubblewrap.

A public report for the same plugin family records internal status `11`:
[Launchpad bug 2119302](https://bugs.launchpad.net/libfprint-2-tod1-broadcom/+bug/2119302).
