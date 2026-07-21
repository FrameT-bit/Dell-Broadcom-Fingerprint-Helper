# Contributing

This project accepts bug fixes only. New features, unrelated fingerprint
readers, non-Ubuntu platforms, and general expansion are out of scope.

Before reporting a bug, run:

```bash
./diagnose.sh | tee fingerprint-report.txt
```

Review the file and remove any personal information. Include:

- laptop manufacturer and model;
- Ubuntu release and kernel version;
- output from `lsusb -d 0a5c:5843`;
- the exact failed operation and result;
- whether `./sandbox.sh check` succeeds;
- whether `./install.sh --dry-run` succeeds.

Never submit biometric templates, IP addresses, service tags, serial numbers,
user names, or host names.

Before submitting a bug fix, run:

```bash
./tests/static.sh
./tests/download-smoke.sh
./sandbox.sh check
```

Do not add `.deb` files, firmware, recovery images, or proprietary binaries to
the repository. Package sources must remain official and checksum-pinned.
