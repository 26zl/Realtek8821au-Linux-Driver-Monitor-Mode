#!/usr/bin/env bash
# Purpose: Configure a Realtek 8821AU/8811AU USB adapter for monitor mode at boot.
# Works across Debian-based desktops (Ubuntu, Mint, Debian) and Raspberry Pi OS.

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

CHANNEL="${CHANNEL:-1}"
if ! [[ "$CHANNEL" =~ ^[0-9]+$ ]]; then
  echo "[monitor_mode] CHANNEL must be an integer value." >&2
  exit 1
fi

TARGET_IFACE="${TARGET_IFACE:-}"
HELPER_PATH="/usr/local/bin/wlan-monitor-8821au.sh"
UNIT_PATH="/etc/systemd/system/wlan-monitor-8821au.service"
NM_CONF_PATH="/etc/NetworkManager/conf.d/10-unmanaged-8821au.conf"

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
  # Fallback: pick the first external-style interface (wlan1, wlx*)
  while IFS=':' read -r _ idxiface _; do
    iface="${idxiface## }"
    iface="${iface%% @*}"
    [[ "$iface" == "wlan0" ]] && continue
    [[ "$iface" == "lo" ]] && continue
    if [[ "$iface" == wl* ]]; then
      echo "$iface"
      return 0
    fi
  done < <(ip -o link show)
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
    echo "               Specify it explicitly: TARGET_IFACE=wlxabc sudo tools/monitor-mode.sh" >&2
    exit 1
  fi
fi

echo "[monitor_mode] Configuring monitor helper for interface '$SELECTED_IFACE' (channel $CHANNEL)."

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
  while IFS=':' read -r _ idxiface _; do
    iface="${idxiface## }"
    iface="${iface%% @*}"
    [[ "$iface" == "wlan0" ]] && continue
    [[ "$iface" == "lo" ]] && continue
    if [[ "$iface" == wl* ]]; then
      echo "$iface"
      return 0
    fi
  done < <(ip -o link show)
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

  if command_exists nmcli; then
    nmcli dev set "$iface" managed no || true
  fi

  sleep 0.5  # allow udev to finish attaching the device
  ip link set "$iface" down || true
  if ! iw dev "$iface" set type monitor 2>/dev/null; then
    LOG "Failed to set '$iface' to monitor mode."
    exit 1
  fi
  ip link set "$iface" up
  iw dev "$iface" set channel "$CHANNEL" || true

  LOG "Now in monitor mode on channel $CHANNEL. Current iw state:"
  iw dev | sed -n "/Interface $iface/,/^$/p"
}

main "$@"
HELPER
chmod +x "$HELPER_PATH"

if command_exists nmcli && systemctl list-unit-files NetworkManager.service >/dev/null 2>&1; then
  mkdir -p /etc/NetworkManager/conf.d
  cat <<EOF > "$NM_CONF_PATH"
[keyfile]
# Automatically managed by monitor-mode.sh 
unmanaged-devices=interface-name:${SELECTED_IFACE}
EOF
  systemctl reload NetworkManager.service 2>/dev/null || systemctl try-restart NetworkManager.service 2>/dev/null || true
else
  echo "[monitor_mode] NetworkManager not detected; skipping persistent unmanaged configuration."
fi

# Write unit file with real line breaks (avoid literal \n in Environment)
cat > "$UNIT_PATH" <<EOF
[Unit]
Description=Put Realtek 8821au adapter into monitor mode at boot
After=systemd-udev-settle.service NetworkManager.service
Wants=systemd-udev-settle.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 3
Restart=on-failure
RestartSec=5
EOF

# Only pin an interface if the user explicitly provided TARGET_IFACE
if [[ -n "${TARGET_IFACE:-}" ]]; then
  echo "Environment=TARGET_IFACE=${SELECTED_IFACE}" >> "$UNIT_PATH"
fi
if [[ "$CHANNEL" != "1" ]]; then
  echo "Environment=CHANNEL=${CHANNEL}" >> "$UNIT_PATH"
fi

cat >> "$UNIT_PATH" <<'EOF'
ExecStart=/usr/local/bin/wlan-monitor-8821au.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now wlan-monitor-8821au.service

echo
echo "[monitor_mode] Monitor mode service enabled. Current iw dev output:"
iw dev
