Check https://github.com/FrameT-bit/Dell-Broadcom-Fingerprint-Helper-GUI for GUI tool

# Dell Broadcom Fingerprint Helper

Sandboxed fingerprint support for Dell Latitude 5420 on Ubuntu.

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
Ubuntu and Latitude 5420 workflow.

## Supported scope

- Dell Latitude 5420
- Broadcom USB device `0a5c:5843`
- Ubuntu and Ubuntu-based distributions on amd64
- Fingerprint enrollment, verification, and PAM authentication

Other systems may happen to work, but they are outside the supported scope.
This community project is not affiliated with or endorsed by Dell, Broadcom,
Canonical, or Ubuntu.

## Recommended: test without installing

The Bubblewrap test environment is the safest way to check compatibility. It
does not install packages, write to `/opt` or `/etc`, replace the host daemon,
or use the host's `/var/lib/fprint` state.

Install the sandbox dependency from Ubuntu:

```bash
sudo apt install bubblewrap
```

No compatibility package is installed by the test. Hardware actions require the
current Ubuntu `libfprint-2-tod1-broadcom` package and refuse its legacy 5.8
firmware package. The safe `check` action does not need firmware access.

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
differs from the firmware reference files supplied by the current Ubuntu
Broadcom package. The script displays this warning and requires explicit
confirmation before exposing the USB bus. Enrollment may also change
fingerprint data held by the sensor.

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
used. The helper relies on the firmware reference files from Ubuntu's currently
installed Broadcom package. Making those files read-only protects the host
filesystem, but cannot prevent USB firmware commands sent by proprietary code.

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
sudo pam-auth-update
```

Select **Fingerprint authentication**. Always keep password authentication
available as a fallback.

The installer refuses to overwrite an unrelated systemd `ExecStart` override.
Remove or disable an old override deliberately before installing this helper.

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
