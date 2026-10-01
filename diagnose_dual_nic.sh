#!/bin/bash
# Standalone before/after network capture for the dual-NIC instability
# (Vogui wifi + UR5 ethernet). Only needed if setup_dual_nic_network.sh
# doesn't fully fix the ping loss to the Vogui.
#
# Meant to be run in one sitting, unattended: connect to the Vogui's wifi
# first (you'll lose your regular internet/remote-access connection while on
# it), then run this script. It pauses locally with a plain `read`, so it
# doesn't need any external session to still be reachable -- just plug in
# the UR5's ethernet cable when it tells you to, then hit Enter. Share the
# resulting .log file afterwards, once reconnected, for review.
set -e

out="dual_nic_diag_$(date +%Y%m%d_%H%M%S).log"

capture() {
  local label="$1"
  {
    echo "===== $label ($(date)) ====="
    echo "--- ip -4 addr show ---"
    ip -4 addr show
    echo "--- ip route show table all ---"
    ip route show table all
    echo "--- ip rule show ---"
    ip rule show
    echo "--- rp_filter ---"
    for f in /proc/sys/net/ipv4/conf/*/rp_filter; do
      printf '%s = %s\n' "$f" "$(cat "$f")"
    done
    echo "--- nmcli active connections ---"
    nmcli -f NAME,DEVICE,TYPE con show --active
    echo
  } >>"$out"
}

echo "Make sure the wifi is already associated to the Vogui and the UR5"
echo "ethernet cable is UNPLUGGED, then press Enter to capture the 'before' state."
read -r _

capture "BEFORE (ethernet unplugged)"

echo "Now plug in the UR5's ethernet cable, wait for it to come up, then press Enter."
read -r _

capture "AFTER (ethernet plugged in)"

echo "Wrote $out"
echo "Share this file for review."
