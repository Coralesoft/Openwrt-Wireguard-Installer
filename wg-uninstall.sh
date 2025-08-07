#!/bin/sh
# wg-uninstall.sh — Cleanup script for WireGuard on OpenWrt (with dry-run support)
# Version: 2025.8.1

set -e

# Colours
print_info()  { printf "\033[0;32m%s\033[0m\n" "$1"; }
print_error() { printf "\033[0;31m%s\033[0m\n" "$1"; }

WG_IFACE="wg0"
WIREGUARD_DIR="/etc/wireguard"
DRY_RUN=0

# Dry-run flag?
if [ "$1" = "--dry-run" ]; then
  DRY_RUN=1
  print_info "Running in dry-run mode. No changes will be made."
fi

print_info "This will remove WireGuard interface '$WG_IFACE', all peer configs, related firewall rules,"
print_info "and completely wipe the contents of $WIREGUARD_DIR."
printf "\nAre you sure you want to proceed? [y/N]: "
read -r confirm
case "$confirm" in [yY]) ;; *) print_info "Aborted."; exit 0;; esac

#
# 1) Remove UCI network interface
#
if uci show network."$WG_IFACE" >/dev/null 2>&1; then
  print_info "Removing network interface '$WG_IFACE'…"
  [ "$DRY_RUN" -eq 0 ] && uci delete network."$WG_IFACE"
fi

# 2) Remove all wireguard peer sections (config type '@wireguard_wg0[...]')
for idx in $( \
    uci show network \
    | awk -F'[@\\[\\]]' '/@wireguard_'${WG_IFACE}'\[/ {print $3}' \
    | sort -un \
  ); do
  print_info "Removing peer section '@wireguard_${WG_IFACE}[${idx}]'…"
  [ "$DRY_RUN" -eq 0 ] && uci delete network.@wireguard_${WG_IFACE}[${idx}]
done

[ "$DRY_RUN" -eq 0 ] && {
  uci commit network
  /etc/init.d/network restart
}

#
# 3) Clean up any firewall rules/zones mentioning the interface
#
print_info "Cleaning up firewall rules…"
# 1) List all sections that mention wg0, e.g. @forwarding[1], @rule[5], @zone[3]…
# 2) uniq them
# 3) sort -t'[' -k2,2nr  sorts by the number inside the brackets, descending
sections=$(uci show firewall \
  | grep "$WG_IFACE" \
  | cut -d. -f2 \
  | sort -u \
  | sort -t'[' -k2,2nr)

for section in $sections; do
  print_info "Removing firewall section '$section'…"
  if [ "$DRY_RUN" -eq 0 ]; then
    uci delete firewall."$section" 2>/dev/null || \
      print_info "  → section $section not found, skipping"
  fi
done

[ "$DRY_RUN" -eq 0 ] && {
  uci commit firewall
  /etc/init.d/firewall restart
}

#
# 4) Wipe out /etc/wireguard entirely (all keys, configs, peers dir, etc)
#
print_info "Wiping all contents of $WIREGUARD_DIR…"
if [ "$DRY_RUN" -eq 0 ] && [ -d "$WIREGUARD_DIR" ]; then
  # find ... -mindepth 1 ensures we delete everything inside, but not the directory itself
  find "$WIREGUARD_DIR" -mindepth 1 -exec rm -rf {} +
fi

#
# 5) Remove any live WireGuard link
#
if ip link show "$WG_IFACE" >/dev/null 2>&1; then
  print_info "Deleting live WireGuard interface '$WG_IFACE'…"
  [ "$DRY_RUN" -eq 0 ] && ip link delete "$WG_IFACE"
fi

print_info ""
if [ "$DRY_RUN" -eq 1 ]; then
  print_info "Dry-run complete. No changes were made."
else
  print_info "WireGuard uninstalled and cleaned up successfully."
fi
