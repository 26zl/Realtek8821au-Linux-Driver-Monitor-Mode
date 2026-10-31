# Security policy

## Reporting a vulnerability

Report security problems in the parts this fork adds privately through
GitHub:
[Report a vulnerability](https://github.com/26zl/Realtek8821au-Linux-Driver-Monitor-Mode/security/advisories/new)
(the Security tab of this repository). Do not open a public issue for
something that could be exploited before it is fixed. Expect a first reply
within seven days; the fix lands on `final`, the default branch, and the
advisory is published once it is in.

## What belongs here and what belongs upstream

This repository is a fork of
[morrownr/8821au-20210708](https://github.com/morrownr/8821au-20210708). The
driver itself, everything under `core/`, `hal/`, `include/`, `os_dep/` and
`platform/`, its build and the DKMS handling in `install-driver.sh` are
maintained upstream. A vulnerability there should be reported to the upstream
project; this fork only merges its fixes.

Reports for this repository cover what the fork adds, all of which runs as
root:

- `tools/monitor-mode.sh` and what it installs: the boot helper
  `/usr/local/bin/wlan-monitor-8821au.sh`, the systemd unit
  `wlan-monitor-8821au.service`, the udev rule
  `/etc/udev/rules.d/90-8821au-monitor.rules` and the NetworkManager or
  connman configuration that keeps the adapter unmanaged. For example an
  interface name or an environment value (`TARGET_IFACE`, `CHANNEL`) that
  reaches a shell unquoted, or a file written outside those paths.
- The clean-up of the same files in `remove-driver.sh`.
- `tools/channel-hop.sh` and `tools/status.sh`.
- The `Monitor` and `NoPrompt` arguments added to `install-driver.sh`.

Putting an adapter into monitor mode is the purpose of this fork. What you
capture with it is your responsibility under local law, not a vulnerability
in the scripts.

## Supported versions

There are no releases. Only the `final` branch is supported; run
`sudo ./install-driver.sh` again after pulling to pick up fixes.
