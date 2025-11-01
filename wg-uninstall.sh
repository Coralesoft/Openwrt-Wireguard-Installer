#!/bin/sh
# wg-uninstall.sh — Cleanup script for WireGuard on OpenWrt
#
# Description:
#   Completely removes WireGuard configuration, keys, and firewall rules.
#   Supports dry-run mode to preview changes before execution.
#
# Version: 2025.11.2
#
# Copyright (c) 2025 C.Brown CoraleSoft
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -e
trap 'print_error "Error on line $LINENO"; exit 1' ERR

# Colors
print_info()  { printf "\033[0;32m%s\033[0m\n" "$1"; }
print_error() { printf "\033[0;31m%s\033[0m\n" "$1"; }
print_warn()  { printf "\033[0;33m%s\033[0m\n" "$1"; }
print_prompt() { printf "\033[0;33m%s\033[0m"   "$1"; }

WG_IFACE="wg0"
WIREGUARD_DIR="/etc/wireguard"
DRY_RUN=0

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      print_info "Running in dry-run mode. No changes will be made."
      ;;
    --interface=*)
      WG_IFACE="${1#*=}"
      ;;
    --help|-h)
      cat <<EOF
Usage: $0 [OPTIONS]

Description:
  Completely removes WireGuard VPN server configuration from OpenWrt.
  This will delete all keys, peer configs, network settings, and firewall rules.

Options:
  --dry-run           Preview changes without making them
  --interface=NAME    Specify WireGuard interface to remove (default: wg0)
  --help             Show this help message

Examples:
  $0                        # Remove wg0 configuration
  $0 --dry-run              # Preview what will be removed
  $0 --interface=wg1        # Remove wg1 configuration

Warning:
  This operation cannot be undone. Make sure you have backups!
EOF
      exit 0
      ;;
    *)
      print_error "Unknown option: $1"
      print_info "Use --help for usage information"
      exit 1
      ;;
  esac
  shift
done

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

# 2) Remove all wireguard peer sections
for section in $(uci show network 2>/dev/null | grep "=wireguard_${WG_IFACE}$" | cut -d. -f2 | cut -d= -f1); do
  print_info "Removing peer section '$section'…"
  [ "$DRY_RUN" -eq 0 ] && uci delete network."$section"
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
  find "$WIREGUARD_DIR" -mindepth 1 -exec rm -rf {} + 2>/dev/null || true
fi

#
# 5) Remove /etc/wireguard from backup configuration
#
if [ -f /etc/sysupgrade.conf ]; then
  if grep -q "^/etc/wireguard" /etc/sysupgrade.conf 2>/dev/null; then
    print_info "Removing /etc/wireguard from backup configuration…"
    if [ "$DRY_RUN" -eq 0 ]; then
      sed -i "/^\/etc\/wireguard$/d" /etc/sysupgrade.conf
    fi
  fi
fi

#
# 6) Remove any live WireGuard link
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
