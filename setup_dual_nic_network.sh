#!/bin/bash
# One-time-per-boot host prerequisite for running the vogui_ros1_ros2_bridge
# while the UR5e is also connected via ethernet.
#
# IPs come from .env (see .env.example) so this script can be committed
# without leaking the real network addresses.
#
# The UR5 controller and the Vogui both live inside the same /24 subnet on
# this host, even though they're reached over two completely separate
# physical links (a direct ethernet cable and wifi). Each interface
# therefore has its own directly-connected route to that same /24 prefix:
#
#   192.168.0.0/24 dev enp0s31f6 metric 100   (ethernet, to the UR5)
#   192.168.0.0/24 dev wlp0s20f3 metric 600   (wifi, to the Vogui)
#
# With two routes to the same prefix, the kernel picks the lower metric --
# ethernet. So once the UR5's cable is plugged in, *everything* addressed in
# 192.168.0.0/24, including pings to the Vogui, gets sent out the ethernet
# cable to the UR5, which obviously never replies on the Vogui's behalf.
# Wifi never disconnects -- it just stops being used for that traffic.
#
# Fix: add host-specific (/32) routes pinning each robot to its actual
# interface. A /32 route is always more specific than either /24 route, so
# it wins regardless of interface metric -- no need to reassign either
# robot's IP or touch NetworkManager profiles.
#
# Same "pin it explicitly instead of trusting auto-selection" pattern as
# setup_multicast_route.sh. Like that script, these routes don't survive a
# reboot -- re-run this once after each boot, once both links are up.
set -e

# Hardcoded directly for now instead of coming from .env (see git history /
# .env.example if reverting to the env-var version).
VOGUI_IP=192.168.0.200
UR5_IP=192.168.0.101

wifi_iface=$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2=="wifi" {print $1; exit}')
eth_iface=$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2=="ethernet" {print $1; exit}')

if [ -z "$wifi_iface" ]; then
  echo "Could not find an active wifi interface. Connect to the Vogui's wifi first." >&2
  exit 1
fi

if [ -z "$eth_iface" ]; then
  echo "Could not find an active ethernet interface. Plug in the UR5's cable first." >&2
  exit 1
fi

echo "Wifi (Vogui) interface: $wifi_iface"
echo "Ethernet (UR5) interface: $eth_iface"

pin_host_route() {
  local host="$1" iface="$2"
  local current
  current=$(ip route show "${host}/32" | awk '{for (i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}')
  if [ "$current" = "$iface" ]; then
    echo "${host}/32 already pinned to $iface, nothing to do."
  else
    sudo ip route replace "${host}/32" dev "$iface"
    echo "Pinned ${host}/32 -> $iface"
  fi
}

pin_host_route "$VOGUI_IP" "$wifi_iface"
pin_host_route "$UR5_IP" "$eth_iface"

echo "Done. Test with: ping -c 20 $VOGUI_IP"
