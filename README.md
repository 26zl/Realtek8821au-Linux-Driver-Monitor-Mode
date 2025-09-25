# Realtek 8821AU Monitor Mode Toolkit and Driver Install

**Fork of:** https://github.com/morrownr/8821au-20210708

This repository is a fork of `morrownr/8821au-20210708`, which provides the driver for Realtek RTL8811AU/RTL8821AU USB adapters. The upstream project focuses exclusively on the driver itself and does not include any tools or scripts for setting the adapter into monitor mode.

This fork extends the upstream driver by adding an optional, user-friendly monitor mode setup specifically designed for Debian-based systems such as Ubuntu, Linux Mint, Debian, and Raspberry Pi OS. The goal is to offer a streamlined and well-documented experience for wireless capture tools like Aircrack-ng, Wireshark, and Kismet, ensuring consistent workflows across desktop, laptop, and Raspberry Pi deployments.

What you get in this fork:
- DKMS/non-DKMS driver installer for the 8821au module (from upstream)
- An optional monitor-mode helper service, including scripts and a systemd unit, that simplifies enabling and maintaining monitor mode on the adapter
- Helper scripts to adjust driver options and to revert the monitor mode configuration

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

The adapter must be plugged in during boot for the automatic monitor mode service to work reliably.  
If the adapter is plugged in after boot, the monitor mode service may not start automatically.  
In that case, you can simply re-run the monitor mode setup script manually from the cloned repository, for example:

```bash
cd /path/to/Realtek-8821au-driver-with-monitor-mode/tools
sudo ./monitor-mode.sh
or
sudo TARGET_IFACE=<iface> ./monitor-mode.sh
```

For more about the driver, check out the upstream readme.