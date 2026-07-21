# Technical research

## Symptom

On the Latitude 5420 reader with USB ID `0a5c:5843`, current `fprintd` and
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
