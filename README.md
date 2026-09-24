Check https://github.com/FrameT-bit/Dell-Broadcom-Fingerprint-Helper-GUI for GUI tool

# Dell Broadcom Fingerprint Helper

Sandboxed fingerprint support for Dell Latitude 5420 on Ubuntu and Fedora.

This experimental helper provides a compatibility stack for the Broadcom
`0a5c:5843` (BCM58200 ControlVault 3) fingerprint reader found in the Dell
Latitude 5420. It addresses enrollment failures such as
`enroll-disconnected`, `enroll-unknown-error`, and internal device status `11`.

The project was built completely with Codex, including the investigation,
scripts, sandbox, safety checks, tests, and documentation.

## Maintenance policy

This is a finished, narrowly scoped compatibility tool. Do not expect new
features, support for more hardware or distributions, package-version updates,
or continued development. Maintenance is limited to bug fixes in the existing
Latitude 5420 workflow on Debian/Ubuntu derivatives and Fedora-family hosts.

## Supported scope

- Dell Latitude 5420
- Broadcom ControlVault USB readers `0a5c:5841`, `0a5c:5842`, `0a5c:5843`, `0a5c:5844`
  and `0a5c:5845` (the PID varies per part and OEM SKU; the 5420 reports `0a5c:5841`)
- Ubuntu and Ubuntu-based distributions on amd64
- Fedora-family distributions on amd64
- Fingerprint enrollment, verification, and PAM authentication

Other systems may happen to work, but they are outside the supported scope.
This community project is not affiliated with or endorsed by Dell, Broadcom,
Canonical, or Ubuntu.

## Recommended: test without installing

The Bubblewrap test environment is the safest way to check compatibility. It
does not install packages, write to `/opt` or `/etc`, replace the host daemon,
or use the host's `/var/lib/fprint` state.

Install the sandbox dependency:

```bash
sudo apt install bubblewrap      # Debian/Ubuntu
sudo dnf install bubblewrap      # Fedora
```

No compatibility package is installed by the test, and no distribution Broadcom
package is needed: the firmware reference files now travel with the stack, taken
from a pinned Dell/Canonical reference release and mounted read-only. Hardware
actions refuse the legacy 5.8.012.0 firmware release. The safe `check` action
does not need firmware access.

Confirm the reader is present:

```bash
lsusb -d 0a5c:5843
```

Run the default no-hardware check:

```bash
./sandbox.sh check
```

This verifies package checksums, extraction, dynamic dependencies, and the
Bubblewrap environment. It does not expose any physical device and does not
require `sudo`.

Hardware sandbox actions are available separately:

```bash
./sandbox.sh list
./sandbox.sh enroll right-index-finger
./sandbox.sh verify right-index-finger
./sandbox.sh shell
```

The sandbox downloads verified packages, creates a temporary compatibility
stack, and discards its filesystem state when it exits. Network access is
disabled after the packages have been downloaded. Hardware actions additionally
start a private D-Bus and `fprintd`. `sudo` is used only to create the
hardware-capable mount namespace; no files are installed by that command.

Bubblewrap cannot isolate changes made directly to a physical USB device. The
proprietary plugin may update ControlVault firmware when the device version
differs from the firmware reference files mounted by the stack (5.15.010.0 by
default; select another release with `FPRINT_FW_REF=5.12`). The script displays
this warning and requires explicit confirmation before exposing the USB bus.
Enrollment may also change fingerprint data held by the sensor.

## Why the complete stack is necessary

Installing only the Broadcom 5.8 plugin did not fix enrollment. The sensor
accepted all enrollment stages and then disconnected before saving the print.
The working combination is the complete Ubuntu 20.04-era userspace stack:

- `fprintd` 1.90.9
- `libfprint` and TOD 1.90.2
- Broadcom plugin 5.8.012.0
- OpenSSL 1.1, private to the compatibility daemon

Packages are downloaded from Ubuntu, Launchpad, and the Dell/Canonical archive.
Every package has a pinned SHA-256 checksum. Old packages are extracted rather
than installed globally.

The legacy firmware shipped with the old Broadcom package is deliberately not
used. The helper downloads the firmware reference files from a pinned
Dell/Canonical reference release and mounts them read-only where the plugin
expects them, so no host package has to be installed on either distribution
family. Making those files read-only protects the host filesystem, but cannot
prevent USB firmware commands sent by proprietary code.

See [RESEARCH.md](RESEARCH.md) for the test matrix and technical background.

## Optional permanent installation

Run a download and dependency check first:

```bash
./install.sh --dry-run
```

Then install the isolated stack:

```bash
sudo ./install.sh
fprintd-enroll -f right-index-finger
fprintd-verify
```

If fingerprint authentication is not enabled for PAM:

```bash
sudo pam-auth-update                                          # Debian/Ubuntu
sudo authselect enable-feature with-fingerprint               # Fedora
sudo authselect apply-changes                                 # Fedora
```

On Debian/Ubuntu select **Fingerprint authentication**. Always keep password
authentication available as a fallback.

The installer refuses to overwrite an unrelated systemd `ExecStart` override.
Remove or disable an old override deliberately before installing this helper.

## Fedora notes

The port keeps the same private stack and adds the glue Fedora needs:

- `.deb` packages are unpacked with `ar` and `tar`; the dpkg toolset is never
  required.
- Installed package versions are read with `rpm -q` instead of `dpkg-query`.
- The firmware reference files travel with the stack and the unit override
  bind-mounts them read-only at `/var/lib/fprint/fw`, so no Ubuntu Broadcom
  package has to be present on the host.
- Fedora ships `fprintd.service` hardened. `MemoryDenyWriteExecute` and
  `SystemCallFilter` are reset for the compatibility daemon because the
  proprietary plugin is only validated against the unhardened daemon that Ubuntu
  ships. The USB device allowlist (`DeviceAllow=char-usb_device`) and
  `StateDirectory=fprint` are kept.
- No udev rule is installed: the legacy `libfprint` selects the TOD driver by USB
  ID and never reads `LIBFPRINT_DRIVER` (verified with `strings`). The
  distribution `fprintd` and `libfprint` packages stay untouched and keep working
  for other readers.
- SELinux carries no `fprintd` policy module on a stock Fedora install, so the
  compatibility daemon runs unconfined; `./diagnose.sh` reports the mode and the
  module count.
- Fedora's `authselect` profile already enables `with-fingerprint`, so PAM needs
  no change; the installer only warns when it is missing.
- The firmware references are bind-mounted over `/var/lib/fprint/fw`, and the
  installer creates that mount point first: `ProtectSystem=strict` leaves `/var`
  read-only inside the unit namespace, so systemd cannot create the target of a
  bind mount itself and the daemon would abort with `status=226/NAMESPACE`.
  Uninstall removes the directory again when nothing else lives there.
- The first start after installation reprograms the ControlVault firmware whenever
  the mounted reference pack declares a different release than the device carries
  (observed on a 5420: `Updating ControlVault firmware from ??? to 5.8.12.0`,
  **93 s**, SBI `229` -> `122`). Firmware programming must never be interrupted, so
  the unit override sets `TimeoutStartSec=600`: Fedora's stock `45 s` killed the
  daemon in the middle of the flash, `systemctl restart` then failed and the
  installer rolled back a working installation. Do not abort the installer while
  that line is in `journalctl -u fprintd -f`.

`FPRINT_FW_REF` selects the firmware reference release: `5.8` (default, and the
only one the bundled plugin can parse), `5.12` or `5.15`. The 5.12/5.15 packages are
built for the 22.04 `libfprint` 1.94 stack and their plugin needs
`fpi_device_report_finger_status_changes`, which `libfprint` 1.90 does not export,
so those packs only become usable once the stack itself moves to 1.94. With the
default the reference pack *is* the plugin's own package and is downloaded once.
The reference package is pinned per release and `install.sh` verifies that it really
declares the selected release before staging it, so a mismatched package can never
be mounted.

## Known failure signatures

| Log line | Meaning |
| --- | --- |
| `Enrollment failed : Device status = (89)` | The plugin aborted the enrollment; the real cause is in the lines right above it |
| `Data read incorrect from file` / `Cannot read contents of sensor-firmware file` | The mounted firmware pack is not the one the plugin was built for (`FPRINT_FW_REF`) |
| `fprintd-list` says `No devices available` while the reader is present | The compatibility daemon is not the active `fprintd`; run `./diagnose.sh` |
| `libusb couldn't open USB device ... errno=13` | Unprivileged session: the reader nodes are `root:root` with no user ACL |

## Diagnostics

```bash
./diagnose.sh | tee fingerprint-report.txt
```

The report excludes IP addresses, service tags, serial numbers, user names, and
host names. Review all diagnostic output before publishing it.

## Uninstall

```bash
sudo ./uninstall.sh
```

This removes only the isolated stack and its systemd override. Enrolled prints
and PAM configuration are preserved.

## Security

This workaround runs legacy components and a proprietary plugin. Read
[SECURITY.md](SECURITY.md) before using it. Third-party packages are never
committed to this repository; see [NOTICE.md](NOTICE.md).

## Sources

- [Ubuntu archive: fprintd](https://archive.ubuntu.com/ubuntu/pool/main/f/fprintd/)
- [Launchpad: libfprint 1.90.2+tod1](https://launchpad.net/ubuntu/+source/libfprint/1:1.90.2+tod1-0ubuntu1~20.04.4/+build/20415516)
- [Launchpad: libssl1.1](https://launchpad.net/~ubuntu-security/+archive/ubuntu/ppa/+build/22006918)
- [Dell/Canonical archive: Broadcom plugin](http://dell.archive.canonical.com/updates/pool/public/libf/libfprint-2-tod1-broadcom/)
- [Dell Ubuntu recovery image for Latitude 5420](https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=84w0x)

## Contributing

Bug fixes are welcome. Feature additions, support for unrelated devices, and
platform expansion are intentionally out of scope. See
[CONTRIBUTING.md](CONTRIBUTING.md).
