#!/usr/bin/env bash
# Purpose: Hop through Wi-Fi channels on a monitor-mode interface.
# Useful for passive scanning with tools like airodump-ng, Wireshark, or Kismet.
#
# Usage: sudo ./tools/channel-hop.sh <interface> [band] [dwell]
#   interface  - wireless interface in monitor mode (e.g. wlan1)
#   band       - 2.4, 5, or both (default: both)
#   dwell      - seconds to stay on each channel (default: 0.5)
#
# Examples:
#   sudo ./tools/channel-hop.sh wlan1
#   sudo ./tools/channel-hop.sh wlan1 2.4
#   sudo ./tools/channel-hop.sh wlan1 5 1
#   sudo ./tools/channel-hop.sh wlan1 both 0.25

set -euo pipefail

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run this script with sudo." >&2
  exit 1
fi

for binary in ip iw awk; do
  if ! command_exists "$binary"; then
    echo "Required command '$binary' not found. Install it and retry." >&2
    exit 1
  fi
done

if [ $# -lt 1 ]; then
  echo "Usage: $0 <interface> [band] [dwell]" >&2
  echo "  band:  2.4 | 5 | both (default: both)" >&2
  echo "  dwell: seconds per channel (default: 0.5)" >&2
  exit 1
fi

IFACE="$1"
BAND="${2:-both}"
DWELL="${3:-0.5}"

if ! ip link show "$IFACE" >/dev/null 2>&1; then
  echo "Interface '$IFACE' not found. Use 'ip link' to list interfaces." >&2
  exit 1
fi

# Validate dwell so a typo doesn't abort mid-loop with a cryptic 'sleep' error.
if ! [[ "$DWELL" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "Dwell must be a number in seconds, e.g. 0.5 or 1." >&2
  exit 1
fi
if ! awk -v dwell="$DWELL" 'BEGIN { exit(dwell > 0 ? 0 : 1) }'; then
  echo "Dwell must be greater than 0 seconds." >&2
  exit 1
fi

# Require monitor mode up front. Otherwise every 'iw set channel' fails, the
# error is swallowed by 2>/dev/null below, and the loop spins silently forever.
if ! iw dev "$IFACE" info 2>/dev/null | grep -q "type monitor"; then
  echo "Interface '$IFACE' is not in monitor mode." >&2
  echo "Enable it first, e.g.: sudo TARGET_IFACE=$IFACE ./tools/monitor-mode.sh" >&2
  exit 1
fi

# 2.4 GHz channels (1-13, widely available)
CHANNELS_24="1 2 3 4 5 6 7 8 9 10 11 12 13"

# 5 GHz channels (UNII-1, UNII-2, UNII-2 Extended, UNII-3 — includes DFS)
CHANNELS_5="36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140 144 149 153 157 161 165"

case "$BAND" in
  2.4|2.4ghz|2.4GHz|24)
    CHANNELS="$CHANNELS_24"
    BAND_LABEL="2.4 GHz"
    ;;
  5|5ghz|5GHz)
    CHANNELS="$CHANNELS_5"
    BAND_LABEL="5 GHz"
    ;;
  both|all)
    CHANNELS="$CHANNELS_24 $CHANNELS_5"
    BAND_LABEL="2.4 + 5 GHz"
    ;;
  *)
    echo "Unknown band '$BAND'. Use 2.4, 5, or both." >&2
    exit 1
    ;;
esac

cleanup() {
  printf "\n"
  echo "Channel hopping stopped on $IFACE."
  exit 0
}
trap cleanup INT TERM

echo "Hopping $BAND_LABEL channels on $IFACE (dwell ${DWELL}s) — Ctrl+C to stop"

while true; do
  for ch in $CHANNELS; do
    # Skip channels blocked by regulatory domain (iw returns non-zero)
    if iw dev "$IFACE" set channel "$ch" 2>/dev/null; then
      printf "\r[channel-hop] %s  ch %-3s  " "$IFACE" "$ch"
    fi
    sleep "$DWELL"
  done
done
