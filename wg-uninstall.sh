#!/bin/sh
# wg-uninstall.sh — Cleanup script for WireGuard setup on OpenWrt (with dry-run support)

set -e

# Colours
print_info()   { printf "\033[0;32m%s\033[0m\n" "$1"; }
print_error()  { printf "\033[0;31m%s\033[0m\n" "$1"; }

WG_IFACE="wg0"
PEERDIR="/etc/wireguard/peers"
DRY_RUN=0

# Check for --dry-run flag
if [ "$1" = "--dry-run" ]; then
  DRY_RUN=1
  print_info "Running in dry-run mode. No changes will be made."
fi

print_info " This will remove WireGuard interface '$WG_IFACE', all peer configs, and related firewall rules."
print_info "Make sure you’ve backed up any important configuration or peer files."

print_info ""
printf "Are you sure you want to proceed? [y/N]: "
read -r confirm
[ "$confirm" = "y" ] || [ "$confirm" = "Y" ] || {
  print_info "Aborted."
  exit 0
}

# Remove network config
if uci get network."$WG_IFACE" >/dev/null 2>&1; then
  print_info "Removing network interface '$WG_IFACE'…"
  [ "$DRY_RUN" -eq 0 ] && uci delete network."$WG_IFACE"
fi

for peer in $(uci show network | grep "^network.wireguard_${WG_IFACE}_" | cut -d. -f2); do
  print_info "Removing peer config section '$peer'…"
  [ "$DRY_RUN" -eq 0 ] && uci delete network."$peer"
done

[ "$DRY_RUN" -eq 0 ] && {
  uci commit network
  /etc/init.d/network restart
}

# Remove firewall rules
print_info "Cleaning up firewall rules…"
uci show firewall | grep "'$WG_IFACE'" | cut -d. -f2 | sort -u | while read -r section; do
  print_info "Removing firewall section '$section'…"
  [ "$DRY_RUN" -eq 0 ] && uci delete firewall."$section"
done

[ "$DRY_RUN" -eq 0 ] && {
  uci commit firewall
  /etc/init.d/firewall restart
}

# Remove keys and peer configs
print_info "Deleting WireGuard keys and peer config files…"
[ "$DRY_RUN" -eq 0 ] && rm -rf /etc/wireguard/privatekey /etc/wireguard/publickey "$PEERDIR"

# Remove live interface
if ip link show "$WG_IFACE" >/dev/null 2>&1; then
  print_info "Removing live WireGuard interface '$WG_IFACE'…"
  [ "$DRY_RUN" -eq 0 ] && ip link delete "$WG_IFACE"
fi

print_info ""
if [ "$DRY_RUN" -eq 1 ]; then
  print_info " Dry-run complete. No changes were made."
else
  print_info "WireGuard uninstalled and cleaned up successfully."
fi
