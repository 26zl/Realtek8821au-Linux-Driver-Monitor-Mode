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
SCRIPT_VERSION="20260211"

MODULE_NAME="8821au"

DRV_NAME="rtl8821au"
DRV_VERSION="5.12.5.2"
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"

OPTIONS_FILE="${MODULE_NAME}.conf"

KARCH="$(uname -m)"
KVER="$(uname -r)"

MODDESTDIR="/lib/modules/${KVER}/kernel/drivers/net/wireless/"
DKMS_UPDATES_DIR="/lib/modules/${KVER}/updates/dkms"

SERVICE="wlan-monitor-8821au.service"
HELPER="/usr/local/bin/wlan-monitor-8821au.sh"
UNIT="/etc/systemd/system/${SERVICE}"
NM_CONF="/etc/NetworkManager/conf.d/10-unmanaged-8821au.conf"
UDEV_RULE="/etc/udev/rules.d/90-8821au-monitor.rules"
CONNMAN_MARKER="/etc/connman/.8821au-monitor-marker"

# Tracks whether any removal step failed, so the final message is honest instead
# of always claiming success.
REMOVE_FAILED=0

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
			*8821au*|*8811au*)
				echo "$iface"
				return 0
				;;
		esac
	done

	# No blind fallback: re-managing an arbitrary unrelated adapter is worse than
	# doing nothing. Removing NM_CONF already restores default management for our
	# device on the next reload.
	return 1
}

remove_monitor_helper() {
	echo "Removing monitor-mode helper (if present)..."

	if command_exists systemctl; then
		systemctl disable --now "$SERVICE" 2>/dev/null || true
	fi
	rm -f "$UNIT" "$HELPER" "$NM_CONF"

	# Remove udev hot-plug rule
	if [ -f "$UDEV_RULE" ]; then
		rm -f "$UDEV_RULE"
		udevadm control --reload-rules 2>/dev/null || true
	fi

	# Remove connman blacklist entry
	if [ -f "$CONNMAN_MARKER" ]; then
		marker_iface="$(cat "$CONNMAN_MARKER" 2>/dev/null || true)"
		if [ -n "$marker_iface" ] && [ -f /etc/connman/main.conf ]; then
			# Remove only the exact interface token from the comma-separated
			# blacklist, leaving other interfaces' config intact. A substring
			# sed would turn e.g. eth0,wlan10,wlan1 into eth00 when removing wlan1.
			if awk -v iface="$marker_iface" '
					/^NetworkInterfaceBlacklist=/ {
						n = split(substr($0, index($0, "=") + 1), a, ",")
						out = ""
						for (i = 1; i <= n; i++)
							if (a[i] != iface && a[i] != "")
								out = (out == "" ? a[i] : out "," a[i])
						if (out == "") next
						print "NetworkInterfaceBlacklist=" out
						next
					}
					{ print }
				' /etc/connman/main.conf > /etc/connman/main.conf.tmp; then
				mv /etc/connman/main.conf.tmp /etc/connman/main.conf
			else
				rm -f /etc/connman/main.conf.tmp
			fi
		fi
		rm -f "$CONNMAN_MARKER"
	fi

	if command_exists systemctl; then
		systemctl daemon-reload 2>/dev/null || true
	fi

	iface="$TARGET_IFACE"
	if [ -z "$iface" ]; then
		iface=$(find_8821au_iface 2>/dev/null || true)
	fi

	# Re-manage the interface in whichever network manager is active
	if [ -n "$iface" ]; then
		if command_exists nmcli; then
			nmcli dev set "$iface" managed yes 2>/dev/null || true
			( systemctl reload NetworkManager 2>/dev/null || nmcli general reload 2>/dev/null ) || true
		elif command_exists connmanctl; then
			connmanctl enable wifi 2>/dev/null || true
			systemctl try-restart connman.service 2>/dev/null || true
		fi
	fi
}

if [ "$(id -u)" -ne 0 ]; then
	echo "You must run this script with superuser (root) privileges."
	echo "Try: \"sudo ./${SCRIPT_NAME}\""
	exit 1
fi

# Work from the driver source tree regardless of the caller's directory, so the
# cleanup target below never runs in an unrelated directory.
cd "$SCRIPT_DIR" || exit 1

print_usage() {
	echo "Syntax $0 [NoPrompt] [TARGET_IFACE=name]"
	echo "       NoPrompt       - noninteractive mode"
	echo "       TARGET_IFACE=x - interface to hand back to NetworkManager"
	echo "       -h|--help      - Show help"
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
	/sbin/depmod -a "${KVER}" || REMOVE_FAILED=1
fi

if [ -f "${MODDESTDIR}rtl${MODULE_NAME}.ko" ]; then
	echo "Removing a non-dkms installation: ${MODDESTDIR}rtl${MODULE_NAME}.ko"
	rm -f "${MODDESTDIR}rtl${MODULE_NAME}.ko"
	/sbin/depmod -a "${KVER}" || REMOVE_FAILED=1
fi

if [ -f "/usr/lib/modules/${KVER}/kernel/drivers/net/wireless/${DRV_NAME}/${MODULE_NAME}.ko.xz" ]; then
	echo "Removing a non-dkms installation: /usr/lib/modules/${KVER}/kernel/drivers/net/wireless/${DRV_NAME}/${MODULE_NAME}.ko.xz"
	rm -f "/usr/lib/modules/${KVER}/kernel/drivers/net/wireless/${DRV_NAME}/${MODULE_NAME}.ko.xz"
	/sbin/depmod -a "${KVER}" || REMOVE_FAILED=1
fi

# check for and remove dkms-installed module in the standard updates path
if [ -f "${DKMS_UPDATES_DIR}/${MODULE_NAME}.ko" ]; then
    echo "Removing dkms-installed module: ${DKMS_UPDATES_DIR}/${MODULE_NAME}.ko"
    rm -f "${DKMS_UPDATES_DIR}/${MODULE_NAME}.ko"
    /sbin/depmod -a "${KVER}" || REMOVE_FAILED=1
fi

if [ -f "${DKMS_UPDATES_DIR}/${MODULE_NAME}.ko.xz" ]; then
    echo "Removing dkms-installed compressed module: ${DKMS_UPDATES_DIR}/${MODULE_NAME}.ko.xz"
    rm -f "${DKMS_UPDATES_DIR}/${MODULE_NAME}.ko.xz"
    /sbin/depmod -a "${KVER}" || REMOVE_FAILED=1
fi

if command_exists dkms; then
	dkms_status_file=$(mktemp) || exit 1
	if dkms status > "$dkms_status_file"; then
		while IFS="/,: " read -r drvname drvver kerver _dummy; do
			[ -n "$drvname" ] || continue
			[ -n "$drvver" ] || continue
			[ -n "$kerver" ] || continue
			case "$drvname" in *${MODULE_NAME})
				if [ "${kerver}" = "added" ]; then
					dkms remove -m "${drvname}" -v "${drvver}" --all || REMOVE_FAILED=1
				else
					dkms remove -m "${drvname}" -v "${drvver}" -k "${kerver}" -c "/usr/src/${drvname}-${drvver}/dkms.conf" || REMOVE_FAILED=1
				fi
				;;
			esac
		done < "$dkms_status_file"
	else
		REMOVE_FAILED=1
	fi
	rm -f "$dkms_status_file"
	if [ -d /usr/src/${DRV_NAME}-${DRV_VERSION} ]; then
		echo "Removing source files from /usr/src/${DRV_NAME}-${DRV_VERSION}"
		rm -r /usr/src/${DRV_NAME}-${DRV_VERSION} || REMOVE_FAILED=1
	fi
fi

# Ensure options file is removed regardless of dkms/non-dkms path
if [ -f /etc/modprobe.d/${OPTIONS_FILE} ]; then
	echo "Removing ${OPTIONS_FILE} from /etc/modprobe.d"
	rm -f /etc/modprobe.d/${OPTIONS_FILE}
fi

# Try to unload the module if it is still loaded, then refresh module deps
if lsmod | awk '{print $1}' | grep -qx "${MODULE_NAME}"; then
    echo "Attempting to unload module: ${MODULE_NAME}"
    /sbin/modprobe -r "${MODULE_NAME}" 2>/dev/null || rmmod "${MODULE_NAME}" 2>/dev/null || true
fi
/sbin/depmod -a "${KVER}" 2>/dev/null || true

make clean >/dev/null 2>&1 || true
if [ "$REMOVE_FAILED" -ne 0 ]; then
	echo "Removal completed, but one or more steps reported errors (see output above)."
else
	echo "The driver and monitor-mode helper were removed successfully."
fi
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
