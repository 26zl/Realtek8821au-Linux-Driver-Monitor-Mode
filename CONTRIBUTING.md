# Contributing

This fork adds persistent monitor mode to the upstream RTL8821AU driver:
`tools/monitor-mode.sh` with the boot helper, systemd unit and udev rule it
installs, `tools/channel-hop.sh`, `tools/status.sh`, the `Monitor` and
`NoPrompt` arguments of `install-driver.sh` and the matching clean-up in
`remove-driver.sh`. Contributions here are about those parts.

Driver code (`core/`, `hal/`, `include/`, `os_dep/`, `platform/`), build
fixes for new kernels and compiler support belong upstream in
[morrownr/8821au-20210708](https://github.com/morrownr/8821au-20210708) and
reach this fork through merges of upstream `main`. `README.md` is the fork's
own (`merge=ours` in `.gitattributes`), so README changes are made here.

## Branches

`final` is the default branch and the base for pull requests. The workflows
also run for a `work-in-progress` branch when one exists. `final` is never
rebased or force-pushed.

## Before you open a pull request

The scripts have to work on the distributions the README lists (Debian,
Ubuntu, Mint, Raspberry Pi OS, Arch, Fedora) with NetworkManager, iwd or
connman. Test on real hardware where you can and say in the pull request
which distribution and network manager you used. Locally run what CI runs:

```bash
find . -type f -name '*.sh' -print0 | xargs -0 -n1 shellcheck        # Shellcheck CI
for t in tests/*.sh; do sh "$t"; done                                 # tests CI
find . -type f \( -name '*.sh' -o -name '*.md' \) -print0 | xargs -0 -n1 codespell
```

`tests/` are shell logic tests that run without root and without an adapter:
they check that the paths the writer (`monitor-mode.sh`), the remover
(`remove-driver.sh`) and the reporter (`status.sh`) use stay identical, that
the embedded boot helper copes with an interface that appears late and with
an unrelated rfkill block, and that the connman blacklist edit is
substring-safe and idempotent. Add a test there when you change that logic.
The Build CI compiles the driver on Ubuntu 22.04 and 24.04 with several GCC
versions; it matters for merges from upstream, not for script changes.

## Style

- `tools/monitor-mode.sh` and `tools/channel-hop.sh` are bash with two-space
  indentation. The upstream scripts (`install-driver.sh`, `remove-driver.sh`,
  `tools/status.sh`, `tools/edit-options.sh`, `tools/save-log.sh`) are POSIX
  sh with tabs, like the driver. Keep each file in its own style;
  `.editorconfig` encodes it.
- The boot helper is written from a heredoc in `monitor-mode.sh`, so every
  installed path appears in `monitor-mode.sh`, `remove-driver.sh` and
  `tools/status.sh`. Change all three; `tests/test-artifact-paths.sh` checks
  that they match.
- Quote every interface name and environment value; the scripts run as root.
- Commit messages are short imperative sentences without a prefix, for
  example `Fix hot-plug rule for rtw88 and input handling in monitor-mode.sh`.

Security problems in the fork's scripts follow [SECURITY.md](SECURITY.md);
driver vulnerabilities go upstream.
