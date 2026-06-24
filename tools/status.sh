#!/bin/sh

# Purpose: Show a quick overview of the 8821au driver, interface, and
#          monitor-mode service status for troubleshooting.
#
# To make this file executable:
#
# $ chmod +x tools/status.sh
#
# To execute this file:
#
# $ sudo ./tools/status.sh

SCRIPT_NAME="tools/status.sh"
MODULE_NAME="8821au"
SERVICE="wlan-monitor-8821au.service"

if [ "$(id -u)" -ne 0 ]; then
	echo "You must run this script with superuser (root) privileges."
	echo "Try: \"sudo ./${SCRIPT_NAME}\""
	exit 1
fi

echo "===== 8821au Status ====="
echo

# Driver module
printf "Driver module: "
if lsmod | awk '{print $1}' | grep -qx "$MODULE_NAME"; then
	echo "LOADED"
else
	echo "NOT LOADED"
fi

# USB device
printf "USB device:    "
if command -v lsusb >/dev/null 2>&1; then
	usb_line="$(lsusb -d 0bda: 2>/dev/null | head -n1)"
	if [ -n "$usb_line" ]; then
		echo "$usb_line"
	else
		echo "no Realtek USB adapter detected"
	fi
else
	echo "lsusb not available"
fi

# Interface detection
echo
echo "Interface"
found_iface=""
for path in /sys/class/net/wlan* /sys/class/net/wlx*; do
	[ -e "$path" ] || continue
	iface="${path##*/}"
	modpath="$(readlink -f "$path/device/driver/module" 2>/dev/null || true)"
	mod="${modpath##*/}"
	case "$mod" in
		*8821au*|*8811au*)
			found_iface="$iface"
			break
			;;
	esac
done

if [ -n "$found_iface" ]; then
	echo "Interface:     $found_iface"

	# Mode
	if command -v iw >/dev/null 2>&1; then
		mode="$(iw dev "$found_iface" info 2>/dev/null | awk '/type/ {print $2}')"
		printf "Mode:          "
		if [ -n "$mode" ]; then
			echo "$mode"
		else
			echo "unknown"
		fi

		# Channel
		chan="$(iw dev "$found_iface" info 2>/dev/null | awk '/channel/ {print $2}')"
		printf "Channel:       "
		if [ -n "$chan" ]; then
			echo "$chan"
		else
			echo "unknown"
		fi
	else
		echo "Mode:          iw not installed"
	fi

	# Link state
	printf "Link state:    "
	operstate="$(cat "/sys/class/net/$found_iface/operstate" 2>/dev/null || echo "unknown")"
	echo "$operstate"
else
	echo "Interface:     no 8821au interface found"
fi

# Systemd service
echo
echo "Monitor Service"
printf "Service:       "
if command -v systemctl >/dev/null 2>&1; then
	if systemctl is-enabled "$SERVICE" >/dev/null 2>&1; then
		state="$(systemctl is-active "$SERVICE" 2>/dev/null)"
		enabled="enabled"
	else
		state="$(systemctl is-active "$SERVICE" 2>/dev/null || true)"
		enabled="disabled"
	fi
	echo "$enabled / $state"
else
	echo "systemctl not available"
fi

# Network Manager
printf "Net manager:   "
if command -v systemctl >/dev/null 2>&1; then
	if systemctl is-active --quiet NetworkManager.service 2>/dev/null; then
		echo "NetworkManager"
	elif systemctl is-active --quiet iwd.service 2>/dev/null; then
		echo "iwd"
	elif systemctl is-active --quiet connman.service 2>/dev/null; then
		echo "connman"
	else
		echo "none detected"
	fi
else
	echo "systemctl not available"
fi

printf "NM unmanaged:  "
NM_CONF="/etc/NetworkManager/conf.d/10-unmanaged-8821au.conf"
if [ -f "$NM_CONF" ]; then
	echo "yes ($NM_CONF)"
else
	echo "no"
fi

printf "Connman block: "
CONNMAN_MARKER="/etc/connman/.8821au-monitor-marker"
if [ -f "$CONNMAN_MARKER" ]; then
	echo "yes ($(cat "$CONNMAN_MARKER" 2>/dev/null))"
else
	echo "no"
fi

# Udev hot-plug rule
printf "Udev hotplug:  "
UDEV_RULE="/etc/udev/rules.d/90-8821au-monitor.rules"
if [ -f "$UDEV_RULE" ]; then
	echo "yes ($UDEV_RULE)"
else
	echo "no"
fi

echo
echo "========================="
