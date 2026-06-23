# Realtek 8821AU Monitor Mode Toolkit and Driver Install

> RTL8821AU/RTL8811AU USB WiFi adapter driver with one-command monitor mode for aircrack-ng, Wireshark, Kismet, and packet capture on Kali Linux, Ubuntu, Arch, Fedora, and Raspberry Pi OS.

**Fork of:** <https://github.com/morrownr/8821au-20210708>

This repository is a fork of `morrownr/8821au-20210708`, which provides the driver for Realtek RTL8811AU/RTL8821AU USB adapters. The upstream project focuses exclusively on the driver itself and does not include any tools or scripts for setting the adapter into monitor mode.

This fork extends the upstream driver by adding an optional, user-friendly monitor mode setup that works across systemd-based distributions: Debian/Ubuntu, Linux Mint, Raspberry Pi OS, Arch Linux, Fedora, and others. The goal is to offer a streamlined and well-documented experience for wireless capture tools like Aircrack-ng, Wireshark, and Kismet, ensuring consistent workflows across desktop, laptop, and Raspberry Pi deployments.

What you get in this fork:

- DKMS/non-DKMS driver installer for the 8821au module (from upstream)
- An optional monitor-mode helper service, including scripts and a systemd unit, that simplifies enabling and maintaining monitor mode on the adapter
- **Hot-plug support** via udev — the adapter automatically enters monitor mode when plugged in, even after boot
- **Multi-distro network manager support** — works with NetworkManager, iwd, and ConnMan
- **Channel hopping script** for passive scanning across 2.4 GHz and 5 GHz bands
- Helper scripts to adjust driver options and to revert the monitor mode configuration

## Driver, hardware & kernel compatibility

This fork documents **only** the monitor-mode additions. Everything about the driver itself — which adapters are supported, which kernels and compilers are tested, supported distributions, and driver build options — is maintained upstream and changes over time. It is intentionally **not duplicated here** so it can never go stale; refer to upstream and the reference files inherited in this repo:

- **Supported kernels, compilers & distros** → see the *Compatible Kernels* / *Tested Compilers* sections of the [upstream README](https://github.com/morrownr/8821au-20210708#readme)
- **Is my adapter supported? (USB device IDs)** → [`supported-device-IDs`](supported-device-IDs)
- **Driver build options** → [`8821au.conf`](8821au.conf), or run `sudo ./tools/edit-options.sh`
- **Driver FAQ & troubleshooting** → [`docs/FAQ.md`](docs/FAQ.md)
- **Concurrent (AP + station) mode** → [`docs/Concurrent_Mode.md`](docs/Concurrent_Mode.md)
- **Anything else about the driver** → [`morrownr/8821au-20210708`](https://github.com/morrownr/8821au-20210708)

## Quick Start

1. Clone this repository and plug in the RTL8821AU/RTL8811AU USB adapter you plan to use.
2. From the repository root, run `sudo ./install-driver.sh`. The installer will detect the adapter, install the driver (DKMS when available), and prompt you to enable monitor mode.
   - Answer `y` and the script installs/enables `wlan-monitor-8821au.service`, so the adapter wakes up in monitor mode automatically after every reboot.
   - Answer `n` (or press Enter) to keep managed mode. You can enable monitor mode later with the helper script.
3. Reboot (recommended) and verify with `sudo systemctl status wlan-monitor-8821au.service` or `iw dev` that the interface is in monitor mode.

### Before vs After

**Without this fork** — 5 manual commands every time you reboot or re-plug the adapter:

```bash
sudo ip link set wlan1 down
sudo iw dev wlan1 set type monitor
sudo ip link set wlan1 up
sudo iw dev wlan1 set channel 6
sudo nmcli dev set wlan1 managed no
```

**With this fork** — one command, persistent across reboots and hot-plugs:

```bash
sudo ./install-driver.sh Monitor NoPrompt
```

### Non-interactive or advanced usage

- `sudo ./install-driver.sh Monitor NoPrompt` installs the driver and enables monitor mode without asking.
- Optional flags such as `TARGET_IFACE=wlxABC123` or `CHANNEL=6` are available when you need to pin a specific interface or default channel, but they are not required for the common single-adapter setup.

## Channel Hopping

The included channel hopping script cycles through Wi-Fi channels on a monitor-mode interface, useful for passive scanning with airodump-ng, Wireshark, or Kismet.

```bash
# Hop all 2.4 + 5 GHz channels (default)
sudo ./tools/channel-hop.sh wlan1

# Hop 2.4 GHz only
sudo ./tools/channel-hop.sh wlan1 2.4

# Hop 5 GHz only, 1 second per channel
sudo ./tools/channel-hop.sh wlan1 5 1

# Fast hopping (0.25s dwell)
sudo ./tools/channel-hop.sh wlan1 both 0.25
```

Press `Ctrl+C` to stop. Channels blocked by your regulatory domain are silently skipped.

**Important — fork & attribution:**
This repository is derived from the upstream work by morrownr. All upstream copyright and license terms still apply. Contributions intended for the original driver should be submitted as pull requests to `morrownr/8821au-20210708`. The monitor mode setup and helper tools included here are **exclusively maintained by this fork** and are not part of the upstream project.

**Important — monitor mode setup is exclusive to this fork:**
The upstream `morrownr/8821au-20210708` repository provides only the driver. This fork adds a dedicated monitor mode helper that automates common tasks such as unmanaging the device in NetworkManager, setting the interface type to monitor, and optionally fixing interface names. This helper is an independent add-on maintained solely by this fork and is not bundled with or supported by the upstream project.

**Important — ethical use only:**
Monitor mode enables passive capture of wireless traffic. It is essential to use this capability responsibly and within the bounds of the law. Do not use these tools to capture, interfere with, or attack networks or devices without explicit authorization. This toolkit is intended strictly for educational purposes, legitimate research, diagnostics, and recovery of systems you are authorized to analyze.

## Current Development Status

**Work in Progress:** This fork is actively being developed to support Android systems by cross-compiling the driver for Android platforms. The aim is to extend the compatibility of the Realtek 8821AU/8811AU driver beyond traditional Linux desktop and server environments to include Android devices.

### What's Currently Being Worked On

- **Android Cross-Compilation Support**: Adapting the driver build system to compile for Android kernels and architectures

### Known Limitations

- **DFS channels**: Some 5 GHz DFS channels may be unavailable depending on your regulatory domain. The channel hopping script and monitor-mode helper silently skip blocked channels.
- **Hot-plug timing**: The udev rule triggers a `systemctl restart` of the monitor-mode service. In rare cases the interface may take a few seconds to stabilize after plugging in. If monitor mode doesn't activate, run `sudo systemctl restart wlan-monitor-8821au.service` manually.
- **Manual fallback**: If automatic detection fails, you can always specify the interface explicitly:

  ```bash
  sudo TARGET_IFACE=wlan1 ./tools/monitor-mode.sh
  ```

### Stuck?

If you run into problems:

- For **monitor-mode, hot-plug, or channel-hopping** problems (the parts this fork adds), open an issue in this repository with details about your system and error messages.
- For **driver-level** issues — adapter not detected, build failures, kernel/compiler support — see [Driver, hardware & kernel compatibility](#driver-hardware--kernel-compatibility) above and the upstream project.
