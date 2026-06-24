#!/usr/bin/env bash
# Purpose: Configure a Realtek 8821AU/8811AU USB adapter for monitor mode at boot.
# Works across Debian-based desktops (Ubuntu, Mint, Debian), Raspberry Pi OS,
# Arch Linux, Fedora, and other systemd-based distributions.

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "[monitor_mode] Please run this script with sudo." >&2
  exit 1
fi

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

for binary in ip iw systemctl; do
  if ! command_exists "$binary"; then
    echo "[monitor_mode] Required command '$binary' not found. Install it and retry." >&2
    exit 1
  fi
done

DEFAULT_CHANNEL=1
CHANNEL="${CHANNEL:-$DEFAULT_CHANNEL}"
if ! [[ "$CHANNEL" =~ ^[0-9]+$ ]] || (( CHANNEL < 1 || CHANNEL > 196 )); then
  echo "[monitor_mode] CHANNEL must be a Wi-Fi channel number between 1 and 196." >&2
  exit 1
fi

TARGET_IFACE="${TARGET_IFACE:-}"

# Kernel driver name for the udev hot-plug rule, sourced from dkms.conf so it
# tracks the package name, with a literal fallback if the read fails.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DRV_NAME="$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p' "$SCRIPT_DIR/../dkms.conf" 2>/dev/null)"
DRV_NAME="${DRV_NAME:-rtl8821au}"
HELPER_PATH="/usr/local/bin/wlan-monitor-8821au.sh"
UNIT_PATH="/etc/systemd/system/wlan-monitor-8821au.service"
NM_CONF_PATH="/etc/NetworkManager/conf.d/10-unmanaged-8821au.conf"
UDEV_RULE_PATH="/etc/udev/rules.d/90-8821au-monitor.rules"
CONNMAN_MARKER="/etc/connman/.8821au-monitor-marker"

# Detect which network manager is active on this system.
# Returns: "NetworkManager", "iwd", "connman", or "none"
detect_net_manager() {
  if systemctl is-active --quiet NetworkManager.service 2>/dev/null; then
    echo "NetworkManager"
  elif systemctl is-active --quiet iwd.service 2>/dev/null; then
    echo "iwd"
  elif systemctl is-active --quiet connman.service 2>/dev/null; then
    echo "connman"
  elif command_exists nmcli; then
    echo "NetworkManager"
  elif command_exists iwctl; then
    echo "iwd"
  elif command_exists connmanctl; then
    echo "connman"
  else
    echo "none"
  fi
}

find_8821au_iface() {
  local iface modpath mod
  for path in /sys/class/net/wlan* /sys/class/net/wlx*; do
    [ -e "$path" ] || continue
    iface="$(basename "$path")"
    modpath="$(readlink -f "$path/device/driver/module" 2>/dev/null || true)"
    mod="$(basename "$modpath" 2>/dev/null || true)"
    if [[ "$mod" == *"8821au" ]] || [[ "$mod" == *"8811au" ]] || [[ "$mod" == "rtw88_8821au" ]]; then
      echo "$iface"
      return 0
    fi
  done
  # Avoid guessing. Putting a random wlan/wlp interface into monitor mode can
  # break the user's primary Wi-Fi connection; ask for TARGET_IFACE instead.
  return 1
}

SELECTED_IFACE="$TARGET_IFACE"
if [[ -n "$SELECTED_IFACE" ]]; then
  if ! ip link show "$SELECTED_IFACE" >/dev/null 2>&1; then
    echo "[monitor_mode] Interface '$SELECTED_IFACE' not found. Use 'ip link' to list interfaces." >&2
    exit 1
  fi
else
  if ! SELECTED_IFACE="$(find_8821au_iface)"; then
    echo "[monitor_mode] Unable to detect an 8821au-driven interface." >&2
    echo "               Specify it explicitly: sudo TARGET_IFACE=wlxabc ./tools/monitor-mode.sh" >&2
    exit 1
  fi
fi

NET_MANAGER="$(detect_net_manager)"
echo "[monitor_mode] Detected network manager: $NET_MANAGER"
echo "[monitor_mode] Configuring monitor helper for interface '$SELECTED_IFACE' (channel $CHANNEL)."

# From here on we write privileged files (helper, NM/connman config, unit, udev
# rule). If any step fails, the install is partial — point the user at teardown.
on_error() {
  echo "[monitor_mode] Setup failed partway through; some files may have been written." >&2
  echo "[monitor_mode] Run 'sudo ./remove-driver.sh' to clean up, then retry." >&2
}
trap on_error ERR

# Write the helper script (runs at boot / service restart)
cat <<'HELPER' > "$HELPER_PATH"
#!/usr/bin/env bash
set -euo pipefail

LOG() { echo "[wlan-monitor-8821au] $*"; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

CHANNEL="${CHANNEL:-1}"
TARGET_IFACE="${TARGET_IFACE:-}"

find_iface() {
  local iface modpath mod
  for path in /sys/class/net/wlan* /sys/class/net/wlx*; do
    [ -e "$path" ] || continue
    iface="$(basename "$path")"
    modpath="$(readlink -f "$path/device/driver/module" 2>/dev/null || true)"
    mod="$(basename "$modpath" 2>/dev/null || true)"
    if [[ "$mod" == *"8821au" ]] || [[ "$mod" == *"8811au" ]] || [[ "$mod" == "rtw88_8821au" ]]; then
      echo "$iface"
      return 0
    fi
  done
  # Avoid guessing. Putting a random wlan/wlp interface into monitor mode can
  # break the user's primary Wi-Fi connection; ask for TARGET_IFACE instead.
  return 1
}

wait_for_iface() {
  local target="$1" discovered="" attempts=0
  local max_attempts=30

  while (( attempts < max_attempts )); do
    if [[ -n "$target" ]]; then
      if ip link show "$target" >/dev/null 2>&1; then
        echo "$target"
        return 0
      fi
    else
      discovered="$(find_iface || true)"
      if [[ -n "$discovered" ]]; then
        echo "$discovered"
        return 0
      fi
    fi

    if (( attempts == 0 )); then
      if [[ -n "$target" ]]; then
        LOG "Waiting for interface '$target' to appear..."
      else
        LOG "Waiting for an 8821au interface to be ready..."
      fi
    fi

    sleep 1
    ((attempts++))
  done

  return 1
}

main() {
  for binary in ip iw; do
    if ! command_exists "$binary"; then
      LOG "Missing required binary '$binary'. Aborting."
      exit 1
    fi
  done

  command_exists rfkill && rfkill unblock wifi || true

  if command_exists rfkill && rfkill list 2>/dev/null | grep -q "Hard blocked: yes"; then
    LOG "Adapter is hard-blocked (hardware switch). Enable Wi‑Fi and retry."
    exit 1
  fi

  local iface
  if ! iface="$(wait_for_iface "$TARGET_IFACE")"; then
    if [[ -n "$TARGET_IFACE" ]]; then
      LOG "Interface '$TARGET_IFACE' did not become ready in time."
    else
      LOG "No 8821au interface detected after waiting."
    fi
    exit 1
  fi

  LOG "Using interface: $iface"

  # Tell the active network manager to release the interface
  if command_exists nmcli; then
    nmcli dev set "$iface" managed no || true
  elif command_exists iwctl; then
    iwctl station "$iface" disconnect 2>/dev/null || true
  elif command_exists connmanctl; then
    connmanctl disable wifi 2>/dev/null || true
  fi

  sleep 0.5  # allow udev to finish attaching the device
  ip link set "$iface" down || true
  if ! iw dev "$iface" set type monitor 2>/dev/null; then
    LOG "Failed to set '$iface' to monitor mode."
    exit 1
  fi
  ip link set "$iface" up
  if ! iw dev "$iface" set channel "$CHANNEL"; then
    LOG "Warning: could not set channel $CHANNEL (invalid/unsupported); staying on the adapter's default channel."
  fi

  LOG "Now in monitor mode on channel $CHANNEL. Current iw state:"
  iw dev | sed -n "/Interface $iface/,/^$/p"
}

main "$@"
HELPER
chmod +x "$HELPER_PATH"

# Persistent network manager configuration
case "$NET_MANAGER" in
  NetworkManager)
    mkdir -p /etc/NetworkManager/conf.d
    cat <<EOF > "$NM_CONF_PATH"
[keyfile]
# Automatically managed by monitor-mode.sh
unmanaged-devices=interface-name:${SELECTED_IFACE}
EOF
    systemctl reload NetworkManager.service 2>/dev/null || systemctl try-restart NetworkManager.service 2>/dev/null || true
    ;;
  iwd)
    echo "[monitor_mode] iwd ignores monitor-mode interfaces; no persistent config needed."
    ;;
  connman)
    mkdir -p /etc/connman
    CONNMAN_CONF="/etc/connman/main.conf"
    if [ -f "$CONNMAN_CONF" ]; then
      if grep -q "^NetworkInterfaceBlacklist" "$CONNMAN_CONF"; then
        # Append only if the iface is not already an exact comma-separated token
        # on the blacklist line (a plain substring grep would treat wlan1 as
        # already-present when only wlan10 is listed).
        if ! awk -v iface="$SELECTED_IFACE" '
              /^NetworkInterfaceBlacklist=/ {
                n = split(substr($0, index($0, "=") + 1), a, ",")
                for (i = 1; i <= n; i++) if (a[i] == iface) { found = 1 }
              }
              END { exit(found ? 0 : 1) }
            ' "$CONNMAN_CONF"; then
          # Append in place so main.conf keeps its owner/mode/SELinux context.
          # A mktemp in /tmp + cross-filesystem mv would reset them to
          # 0600/root/tmp_t and can make connman unable to read its own config.
          # Interface names are alphanumeric, so no sed metachars to escape.
          sed -i "/^NetworkInterfaceBlacklist=/ s/\$/,${SELECTED_IFACE}/" "$CONNMAN_CONF"
        fi
      else
        echo "NetworkInterfaceBlacklist=${SELECTED_IFACE}" >> "$CONNMAN_CONF"
      fi
    else
      cat <<EOF > "$CONNMAN_CONF"
[General]
NetworkInterfaceBlacklist=${SELECTED_IFACE}
EOF
    fi
    echo "$SELECTED_IFACE" > "$CONNMAN_MARKER"
    systemctl try-restart connman.service 2>/dev/null || true
    ;;
  *)
    echo "[monitor_mode] No supported network manager detected; skipping persistent unmanaged configuration."
    ;;
esac

# Determine After= dependency for the systemd unit
case "$NET_MANAGER" in
  NetworkManager) AFTER_SERVICE="NetworkManager.service" ;;
  iwd)            AFTER_SERVICE="iwd.service" ;;
  connman)        AFTER_SERVICE="connman.service" ;;
  *)              AFTER_SERVICE="" ;;
esac

# Write systemd unit file
cat > "$UNIT_PATH" <<EOF
[Unit]
Description=Put Realtek 8821au adapter into monitor mode at boot
After=systemd-udev-settle.service${AFTER_SERVICE:+ $AFTER_SERVICE}
Wants=systemd-udev-settle.service

[Service]
Type=oneshot
EOF

# Only pin an interface if the user explicitly provided TARGET_IFACE
if [[ -n "${TARGET_IFACE:-}" ]]; then
  echo "Environment=TARGET_IFACE=${SELECTED_IFACE}" >> "$UNIT_PATH"
fi
if [[ "$CHANNEL" != "$DEFAULT_CHANNEL" ]]; then
  echo "Environment=CHANNEL=${CHANNEL}" >> "$UNIT_PATH"
fi

cat >> "$UNIT_PATH" <<'EOF'
ExecStart=/usr/local/bin/wlan-monitor-8821au.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Install udev rule for hot-plug support
echo "[monitor_mode] Installing udev rule for hot-plug support..."
SYSTEMCTL_PATH="$(command -v systemctl)"
cat > "$UDEV_RULE_PATH" <<EOF
# Automatically restart the monitor-mode service when the 8821au adapter is plugged in.
# Managed by monitor-mode.sh - do not edit manually.
ACTION=="add", SUBSYSTEM=="net", DRIVERS=="${DRV_NAME}", RUN+="$SYSTEMCTL_PATH --no-block restart wlan-monitor-8821au.service"
EOF
udevadm control --reload-rules 2>/dev/null || true

systemctl daemon-reload
# Enable persistently first, then start best-effort: a oneshot 'start' fails if
# the adapter isn't ready yet, but the install itself is complete and the udev
# rule will start it on the next plug-in/boot.
systemctl enable wlan-monitor-8821au.service
trap - ERR
if ! systemctl start wlan-monitor-8821au.service; then
  echo "[monitor_mode] Service enabled but it could not start now (adapter may not be ready)."
  echo "[monitor_mode] It will activate automatically on the next plug-in or reboot."
fi

echo
echo "[monitor_mode] Monitor mode service enabled (with hot-plug udev rule). Current iw dev output:"
iw dev
