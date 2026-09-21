# Security

This helper is a compatibility workaround, not a security update. It uses
legacy `fprintd`, `libfprint`, and OpenSSL 1.1 versions because the tested
Broadcom plugin depends on that combination.

Mitigations included in the project:

- every download has a pinned SHA-256 checksum and is rejected on mismatch;
- legacy libraries remain private and do not replace distribution packages;
- Bubblewrap tests use temporary filesystem and D-Bus state;
- sandbox network access is disabled after downloads finish;
- firmware reference files are mounted read-only from the private stack,
  preventing host-file changes on Debian/Ubuntu and Fedora alike;
- a permanent installation is rolled back if its daemon does not start;
- uninstalling restores the distribution daemon.

Fedora ships `fprintd.service` with `MemoryDenyWriteExecute=true` and a
`SystemCallFilter` allowlist. The unit override resets both for the
compatibility daemon only, because the proprietary plugin is validated against
the unhardened daemon Ubuntu ships; the USB device allowlist and the private
state directory are kept. This is a deliberate reduction of hardening to match
the reference environment, not an oversight.

The Dell/Canonical archive serves the Broadcom package over HTTP. The pinned
checksum is therefore mandatory protection against modification in transit.
All other downloads use HTTPS and are checksum-verified as well.

Bubblewrap cannot roll back writes sent directly to USB hardware. The Broadcom
plugin contains an automatic ControlVault firmware update path, so the sandbox
requires explicit confirmation before exposing the USB bus.

Remaining risks include vulnerabilities in legacy code, future incompatibility,
physical USB device changes, and the closed-source plugin. Do not use
this workaround in a high-assurance environment without an independent review.
Always retain password authentication.

Do not publish biometric data, IP addresses, service tags, serial numbers, user
names, host names, or unreviewed logs in a security report.
