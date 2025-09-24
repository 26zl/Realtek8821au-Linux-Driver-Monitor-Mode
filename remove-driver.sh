#!/bin/sh

# Purpose: Remove Realtek out-of-kernel USB WiFi adapter drivers and
#          clean up the optional monitor-mode helper.
#
# Supports dkms and non-dkms removals.
#
# To execute this file:
#
# $ sudo ./remove-driver.sh
#
# Optional arguments:
#   NoPrompt         - run without interactive prompts
#   TARGET_IFACE=x   - specify which interface to return to NetworkManager
#
# Examples:
#   $ sudo ./remove-driver.sh NoPrompt
#   $ sudo ./remove-driver.sh TARGET_IFACE=wlan1
#
# Copyright(c) 2024 Nick Morrow
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.

SCRIPT_NAME="remove-driver.sh"
SCRIPT_VERSION="20240314"

MODULE_NAME="8821au"

DRV_NAME="rtl8821au"
DRV_VERSION="5.12.5.2"

OPTIONS_FILE="${MODULE_NAME}.conf"

KARCH="$(uname -m)"
KVER="$(uname -r)"

MODDESTDIR="/lib/modules/${KVER}/kernel/drivers/net/wireless/"

SERVICE="wlan-monitor-8821au.service"
HELPER="/usr/local/bin/wlan-monitor-8821au.sh"
UNIT="/etc/systemd/system/${SERVICE}"
NM_CONF="/etc/NetworkManager/conf.d/10-unmanaged-8821au.conf"

command_exists() {
	command -v "$1" >/dev/null 2>&1
}

find_8821au_iface() {
	for path in /sys/class/net/wlan* /sys/class/net/wlx*; do
		[ -e "$path" ] || continue
		iface=${path##*/}
		modpath=$(readlink -f "$path/device/driver/module" 2>/dev/null)
		mod=${modpath##*/}
		case "$mod" in
			*8821au*)
				echo "$iface"
				return 0
				;;
		esac
	done

	for candidate in wlan1 wlan2 wlan3; do
		if ip link show "$candidate" >/dev/null 2>&1; then
			echo "$candidate"
			return 0
		fi
	done

	for path in /sys/class/net/wl*; do
		[ -e "$path" ] || continue
		iface=${path##*/}
		[ "$iface" = "wlan0" ] && continue
		[ "$iface" = "lo" ] && continue
		echo "$iface"
		return 0
	done

	return 1
}

remove_monitor_helper() {
	echo "Removing monitor-mode helper (if present)..."

	if command_exists systemctl; then
		systemctl disable --now "$SERVICE" 2>/dev/null || true
	fi
	rm -f "$UNIT" "$HELPER" "$NM_CONF"
	if command_exists systemctl; then
		systemctl daemon-reload 2>/dev/null || true
	fi

	iface="$TARGET_IFACE"
	if [ -z "$iface" ]; then
		iface=$(find_8821au_iface 2>/dev/null || true)
	fi

	if [ -n "$iface" ] && command_exists nmcli; then
		nmcli dev set "$iface" managed yes 2>/dev/null || true
	fi
}

if [ "$(id -u)" -ne 0 ]; then
	echo "You must run this script with superuser (root) privileges."
	echo "Try: \"sudo ./${SCRIPT_NAME}\""
	exit 1
fi

print_usage() {
	echo "Syntax $0 [NoPrompt] [TARGET_IFACE=name]"
	echo "       NoPrompt       - noninteractive mode"
	echo "       TARGET_IFACE=x - interface to hand back to NetworkManager"
	echo "       -h|--help       - Show help"
}

NO_PROMPT=0
TARGET_IFACE_ENV="${TARGET_IFACE:-}"

while [ $# -gt 0 ]
do
	case $1 in
		NoPrompt|noprompt|NOPROMPT)
			NO_PROMPT=1 ;;
		TARGET_IFACE=*|TargetIface=*|target_iface=*)
			TARGET_IFACE_ENV=${1#*=} ;;
		-h|--help|help|-help)
			print_usage
			exit 0 ;;
		*)
			echo "Unknown option: $1"
			print_usage
			exit 1 ;;
	esac
	shift
done

TARGET_IFACE="$TARGET_IFACE_ENV"

remove_monitor_helper

echo ": ---------------------------"

echo ": ${SCRIPT_NAME} v${SCRIPT_VERSION}"

echo ": ${KARCH} (kernel architecture)"

echo ": ${KVER} (kernel version)"

echo ": ---------------------------"
echo

if [ -f "${MODDESTDIR}${MODULE_NAME}.ko" ]; then
	echo "Removing a non-dkms installation: ${MODDESTDIR}${MODULE_NAME}.ko"
	rm -f "${MODDESTDIR}${MODULE_NAME}.ko"
	/sbin/depmod -a "${KVER}"
fi

if [ -f "${MODDESTDIR}rtl${MODULE_NAME}.ko" ]; then
	echo "Removing a non-dkms installation: ${MODDESTDIR}rtl${MODULE_NAME}.ko"
	rm -f "${MODDESTDIR}rtl${MODULE_NAME}.ko"
	/sbin/depmod -a "${KVER}"
fi

if [ -f "/usr/lib/modules/${KVER}/kernel/drivers/net/wireless/${DRV_NAME}/${MODULE_NAME}.ko.xz" ]; then
	echo "Removing a non-dkms installation: /usr/lib/modules/${KVER}/kernel/drivers/net/wireless/${DRV_NAME}/${MODULE_NAME}.ko.xz"
	rm -f "/usr/lib/modules/${KVER}/kernel/drivers/net/wireless/${DRV_NAME}/${MODULE_NAME}.ko.xz"
	/sbin/depmod -a "${KVER}"
fi

if command_exists dkms; then
	dkms status | while IFS="/,: " read -r drvname drvver kerver _dummy; do
		case "$drvname" in *${MODULE_NAME})
			if [ "${kerver}" = "added" ]; then
				dkms remove -m "${drvname}" -v "${drvver}" --all
			else
				dkms remove -m "${drvname}" -v "${drvver}" -k "${kerver}" -c "/usr/src/${drvname}-${drvver}/dkms.conf"
			fi
			;;
		esac
	done
	if [ -f /etc/modprobe.d/${OPTIONS_FILE} ]; then
		echo "Removing ${OPTIONS_FILE} from /etc/modprobe.d"
		rm /etc/modprobe.d/${OPTIONS_FILE}
	fi
	if [ -d /usr/src/${DRV_NAME}-${DRV_VERSION} ]; then
		echo "Removing source files from /usr/src/${DRV_NAME}-${DRV_VERSION}"
		rm -r /usr/src/${DRV_NAME}-${DRV_VERSION}
	fi
fi

make clean >/dev/null 2>&1 || true
echo "The driver and monitor-mode helper were removed successfully."
echo "You may now delete the driver directory if desired."
echo ": ---------------------------"
echo

if [ $NO_PROMPT -ne 1 ]; then
	printf "Do you want to reboot now? (recommended) [Y/n] "
	read -r yn
	case "$yn" in
		[nN]) ;;
		*) reboot ;;
	esac
fi
