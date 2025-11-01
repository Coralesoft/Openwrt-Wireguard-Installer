#!/bin/sh
# wg-peer-manage.sh - WireGuard peer management script for OpenWrt
#
# Description:
#   Manages WireGuard peers: add, remove, list, show status, enable/disable.
#   Supports both command-line flags and interactive menu mode.
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

print_info()   { printf "\033[0;32m%s\033[0m\n" "$1"; }
print_error()  { printf "\033[0;31m%s\033[0m\n" "$1"; }
print_warn()   { printf "\033[0;33m%s\033[0m\n" "$1"; }
print_prompt() { printf "\033[0;33m%s\033[0m"   "$1"; }
clear_screen() { [ "$CLEAR_SCREEN" -eq 1 ] && clear; }

# Configuration
WG_IFACE="wg0"
KEYDIR="/etc/wireguard"
PEERDIR="$KEYDIR/peers"
ACTION=""
PEER_NAME=""
INTERACTIVE_MODE=0
CLEAR_SCREEN=1

# Detect qrencode & PNG support
HAS_QR=0
HAS_PNG=0
if command -v qrencode >/dev/null 2>&1; then
  HAS_QR=1
  if printf "[Interface]" | qrencode -t png -o /dev/null 2>&1 | grep -qv "disabled at compile time"; then
    HAS_PNG=1
  fi
fi

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --add)
      ACTION="add"
      ;;
    --remove=*)
      ACTION="remove"
      PEER_NAME="${1#*=}"
      ;;
    --show=*)
      ACTION="show"
      PEER_NAME="${1#*=}"
      ;;
    --list)
      ACTION="list"
      ;;
    --enable=*)
      ACTION="enable"
      PEER_NAME="${1#*=}"
      ;;
    --disable=*)
      ACTION="disable"
      PEER_NAME="${1#*=}"
      ;;
    --traffic)
      ACTION="traffic"
      ;;
    --active)
      ACTION="active"
      ;;
    --interface=*)
      WG_IFACE="${1#*=}"
      ;;
    --no-clear)
      CLEAR_SCREEN=0
      ;;
    --help|-h)
      cat <<EOF
Usage: $0 [OPTIONS]

Options:
  (no options)         Run in interactive menu mode
  --add                Add a new peer interactively
  --remove=NAME        Remove a peer
  --show=NAME          Show peer details and regenerate QR code
  --list               List all configured peers
  --enable=NAME        Enable a disabled peer
  --disable=NAME       Disable a peer without removing it
  --traffic            Show traffic statistics for all peers
  --active             Show only currently connected peers
  --interface=NAME     Specify WireGuard interface (default: wg0)
  --no-clear           Don't clear screen in interactive mode (for scrollers)
  --help              Show this help message

Examples:
  $0                          # Interactive menu mode
  $0 --add                    # Add new peer interactively
  $0 --list                   # List all peers
  $0 --show=laptop            # Show laptop config + QR code
  $0 --remove=old-phone       # Remove peer
  $0 --disable=tablet         # Temporarily disable peer
  $0 --traffic                # View bandwidth usage
  $0 --active                 # See currently connected peers
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

# Ensure required commands
for cmd in wg uci; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    print_error "Missing '$cmd'. Run: opkg update && opkg install wireguard-tools"
    exit 1
  fi
done

# Verify interface exists
if ! uci show network."$WG_IFACE" >/dev/null 2>&1; then
  print_error "WireGuard interface '$WG_IFACE' not found in UCI configuration"
  print_info "Run wg-openwrt-installer.sh first to set up WireGuard"
  exit 1
fi

# Get server configuration
if [ ! -f "$KEYDIR/publickey" ]; then
  print_error "Server public key not found at $KEYDIR/publickey"
  print_info "Run wg-openwrt-installer.sh first to set up WireGuard server"
  exit 1
fi

SERVER_PUB=$(tr -d '\r\n' < "$KEYDIR/publickey")
[ -z "$SERVER_PUB" ] && { print_error "Server public key is empty"; exit 1; }

WG_PORT=$(uci get network."$WG_IFACE".listen_port 2>/dev/null || echo "51820")
SERVER_ADDR=$(uci get network."$WG_IFACE".addresses 2>/dev/null | head -n1)
WG_SUBNET_BASE="$(echo "$SERVER_ADDR" | cut -d/ -f1 | awk -F. '{print $1"."$2"."$3}')"
DEFAULT_DNS="$(echo "$SERVER_ADDR" | cut -d/ -f1)"

#
# FUNCTION: LIST
#
do_list() {
  print_info ""
  print_info "WireGuard Peers on interface '$WG_IFACE':"
  print_info "════════════════════════════════════════"

  peer_list=""
  num=0
  found=0

  for section in $(uci show network 2>/dev/null | grep "=wireguard_${WG_IFACE}$" | cut -d. -f2 | cut -d= -f1); do
    found=1
    num=$((num+1))
    desc=$(uci get network."$section".description 2>/dev/null || echo "$section")
    allowed=$(uci get network."$section".allowed_ips 2>/dev/null | head -n1 || echo "N/A")
    enabled=$(uci get network."$section".disabled 2>/dev/null || echo "0")

    if [ "$enabled" = "1" ]; then
      status="[DISABLED]"
    else
      status="[ENABLED]"
    fi

    print_info "  $num. $desc ($allowed) $status"

    peer_list="$peer_list
$num:$desc"
  done

  if [ "$found" -eq 0 ]; then
    print_warn "  No peers configured."
  fi

  print_info ""
  echo "$peer_list"
}

#
# FUNCTION: SHOW
#
do_show() {
  peer_name="$1"

  if [ -z "$peer_name" ]; then
    print_error "Peer name required"
    return 1
  fi

  # Find UCI section
  uci_section=""
  for section in $(uci show network 2>/dev/null | grep "=wireguard_${WG_IFACE}$" | cut -d. -f2 | cut -d= -f1); do
    desc=$(uci get network."$section".description 2>/dev/null || "")
    if [ "$desc" = "$peer_name" ]; then
      uci_section="$section"
      break
    fi
  done

  if [ -z "$uci_section" ]; then
    print_error "Peer '$peer_name' not found"
    return 1
  fi

  # Get peer details
  pubkey=$(uci get network."$uci_section".public_key 2>/dev/null || echo "N/A")
  allowed=$(uci get network."$uci_section".allowed_ips 2>/dev/null | head -n1 || echo "N/A")
  keepalive=$(uci get network."$uci_section".persistent_keepalive 2>/dev/null || echo "N/A")
  enabled=$(uci get network."$uci_section".disabled 2>/dev/null || echo "0")

  print_info ""
  print_info "Peer Details: $peer_name"
  print_info "════════════════════════════════════════"
  print_info "  Status:      $([ "$enabled" = "1" ] && echo "DISABLED" || echo "ENABLED")"
  print_info "  IP Address:  $allowed"
  print_info "  Public Key:  $pubkey"
  print_info "  Keepalive:   ${keepalive}s"
  print_info ""

  # Show connection status if interface is up
  if wg show "$WG_IFACE" >/dev/null 2>&1; then
    if wg show "$WG_IFACE" | grep -q "$pubkey"; then
      endpoint=$(wg show "$WG_IFACE" peers | grep -A5 "$pubkey" | grep "endpoint:" | awk '{print $2}' || echo "N/A")
      handshake=$(wg show "$WG_IFACE" peers | grep -A5 "$pubkey" | grep "latest handshake:" || echo "  never")
      transfer=$(wg show "$WG_IFACE" peers | grep -A5 "$pubkey" | grep "transfer:" || echo "  0 B received, 0 B sent")

      print_info "Connection Status:"
      print_info "  Endpoint:    $endpoint"
      print_info "  Handshake:   $handshake"
      print_info "  Transfer:    $transfer"
      print_info ""
    else
      print_warn "Peer not currently connected"
      print_info ""
    fi
  fi

  # Show config file if exists
  if [ -f "$PEERDIR/$peer_name.conf" ]; then
    print_info "Configuration file: $PEERDIR/$peer_name.conf"
    print_info ""
    cat "$PEERDIR/$peer_name.conf"
    print_info ""

    # Regenerate QR code
    if [ "$HAS_QR" -eq 1 ]; then
      print_info "QR Code:"
      qrencode -t ansiutf8 < "$PEERDIR/$peer_name.conf"
      print_info ""
    fi
  else
    print_warn "Configuration file not found: $PEERDIR/$peer_name.conf"
    print_info "Run key rotation to regenerate peer configs"
  fi
}

#
# FUNCTION: ADD
#
do_add() {
  print_info ""
  print_info "Add New WireGuard Peer"
  print_info "════════════════════════════════════════"
  print_info ""
  print_info "This will create a new peer configuration with:"
  print_info "  • Unique keypair"
  print_info "  • IP address in VPN subnet"
  print_info "  • QR code for easy mobile setup"
  print_info ""

  # Get peer name
  print_info "→ Peer name"
  print_info "     What: Device/user identifier (e.g., laptop, phone)"
  print_info "     Why : Used to identify this peer in configs"
  print_prompt "   Enter peer name (no spaces): "
  read -r new_peer_name
  new_peer_name=${new_peer_name// /_}

  if [ -z "$new_peer_name" ]; then
    print_error "Peer name required"
    return 1
  fi

  # Check if peer already exists
  for section in $(uci show network 2>/dev/null | grep "=wireguard_${WG_IFACE}$" | cut -d. -f2 | cut -d= -f1); do
    desc=$(uci get network."$section".description 2>/dev/null || "")
    if [ "$desc" = "$new_peer_name" ]; then
      print_error "Peer '$new_peer_name' already exists"
      return 1
    fi
  done

  # Find next available IP - build list of used IPs from all peers
  used_ips=""
  for section in $(uci show network 2>/dev/null | grep "=wireguard_${WG_IFACE}$" | cut -d. -f2 | cut -d= -f1); do
    peer_ip=$(uci get network."$section".allowed_ips 2>/dev/null | head -n1 | cut -d/ -f1)
    if [ -n "$peer_ip" ]; then
      used_ips="$used_ips $peer_ip"
    fi
  done

  # Also include server IP
  server_ip=$(echo "$SERVER_ADDR" | cut -d/ -f1)
  used_ips="$used_ips $server_ip"

  # Find first available IP
  next_ip=""
  for i in $(seq 2 254); do
    candidate="$WG_SUBNET_BASE.$i"
    ip_found=0
    for used in $used_ips; do
      if [ "$used" = "$candidate" ]; then
        ip_found=1
        break
      fi
    done
    if [ "$ip_found" -eq 0 ]; then
      next_ip="$candidate"
      break
    fi
  done

  if [ -z "$next_ip" ]; then
    print_error "No available IPs in subnet $WG_SUBNET_BASE.0/24"
    return 1
  fi

  DEFAULT_PIP="$next_ip/32"
  print_info ""
  print_info "→ Peer IP address"
  print_info "     What: VPN IP for this device"
  print_info "     Why : Must be unique in subnet $WG_SUBNET_BASE.0/24"
  print_prompt "   Allowed IP [$DEFAULT_PIP]: "
  read -r PIP
  PIP=${PIP:-$DEFAULT_PIP}

  # Validate IP format
  case "$PIP" in */32) ;; *) print_error "Must include /32"; return 1;; esac
  if ! echo "$PIP" | grep -q "^$WG_SUBNET_BASE\."; then
    print_error "IP $PIP not in subnet $WG_SUBNET_BASE"
    return 1
  fi

  # Get endpoint
  print_info ""
  print_info "→ Public endpoint"
  print_info "     What: Your OpenWrt's public hostname or IP"
  print_info "     Why : Used by peers to connect to server"
  print_prompt "   Public endpoint [auto-detect]: "
  read -r ENDPOINT
  if [ -z "$ENDPOINT" ]; then
    ENDPOINT="your.openwrt.hostname:$WG_PORT"
  fi
  case "$ENDPOINT" in *:*) ;; *) ENDPOINT="$ENDPOINT:$WG_PORT";; esac

  # Get DNS
  print_info ""
  print_info "→ DNS server for peer"
  print_info "     What: DNS IP to suggest to this peer"
  print_info "     Why : Avoids DNS leaks / enables local name resolution"
  print_prompt "   DNS server [$DEFAULT_DNS]: "
  read -r WG_DNS
  WG_DNS=${WG_DNS:-$DEFAULT_DNS}

  print_info ""
  print_info "Generating peer keypair..."

  # Generate keys
  mkdir -p "$PEERDIR"
  umask 077
  PPRIV=$(wg genkey)
  PPUB=$(printf '%s' "$PPRIV" | wg pubkey)

  printf '%s' "$PPRIV" > "$PEERDIR/$new_peer_name-privatekey"
  printf '%s' "$PPUB" > "$PEERDIR/$new_peer_name-publickey"

  # Create config file
  cat > "$PEERDIR/$new_peer_name.conf" <<EOF
[Interface]
 PrivateKey = $PPRIV
Address = $PIP
DNS = $WG_DNS

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $ENDPOINT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

  print_info "Configuration saved: $PEERDIR/$new_peer_name.conf"
  print_info ""

  # Generate QR codes
  if [ "$HAS_QR" -eq 1 ]; then
    print_info "QR Code:"
    qrencode -t ansiutf8 < "$PEERDIR/$new_peer_name.conf"

    if [ "$HAS_PNG" -eq 1 ]; then
      qrencode -t png -o "$PEERDIR/$new_peer_name.png" < "$PEERDIR/$new_peer_name.conf"
      print_info ""
      print_info "QR PNG saved: $PEERDIR/$new_peer_name.png"
    fi
  fi

  print_info ""
  print_info "Adding peer to UCI configuration..."

  # Add to UCI
  section="wireguard_${WG_IFACE}_${new_peer_name}"
  uci set network.$section=wireguard_${WG_IFACE}
  uci set network.$section.description="$new_peer_name"
  uci set network.$section.public_key="$PPUB"
  uci set network.$section.persistent_keepalive=25
  uci delete network.$section.allowed_ips 2>/dev/null || true
  uci add_list network.$section.allowed_ips="$PIP"
  uci commit network

  print_info ""
  print_info "Peer '$new_peer_name' added successfully!"
  print_info ""
  print_info "Summary:"
  print_info "  Name:     $new_peer_name"
  print_info "  IP:       $PIP"
  print_info "  Endpoint: $ENDPOINT"
  print_info "  DNS:      $WG_DNS"
  print_info ""

  if [ "$INTERACTIVE_MODE" -eq 0 ]; then
    print_prompt "Restart WireGuard interface now? [y/N]: "
    read -r restart
    if [ "${restart##[Yy]}" = "" ]; then
      /etc/init.d/network reload
      print_info "Interface reloaded"
    else
      print_warn "Remember to restart the interface: /etc/init.d/network reload"
    fi
  fi
}

#
# FUNCTION: REMOVE
#
do_remove() {
  peer_name="$1"

  if [ -z "$peer_name" ]; then
    print_error "Peer name required"
    return 1
  fi

  # Find UCI section
  uci_section=""
  for section in $(uci show network 2>/dev/null | grep "=wireguard_${WG_IFACE}$" | cut -d. -f2 | cut -d= -f1); do
    desc=$(uci get network."$section".description 2>/dev/null || "")
    if [ "$desc" = "$peer_name" ]; then
      uci_section="$section"
      break
    fi
  done

  if [ -z "$uci_section" ]; then
    print_error "Peer '$peer_name' not found"
    return 1
  fi

  print_warn ""
  print_warn "This will permanently remove peer '$peer_name'"
  print_prompt "Are you sure? [y/N]: "
  read -r confirm

  if [ "${confirm##[Yy]}" != "" ]; then
    print_info "Cancelled"
    return 0
  fi

  print_info ""
  print_info "Removing peer '$peer_name'..."

  # Remove from UCI
  uci delete network.$uci_section
  uci commit network

  # Archive peer files
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  ARCHIVE_DIR="$KEYDIR/removed/$TIMESTAMP-$peer_name"
  mkdir -p "$ARCHIVE_DIR"

  if [ -f "$PEERDIR/$peer_name.conf" ]; then
    mv "$PEERDIR/$peer_name.conf" "$ARCHIVE_DIR/" 2>/dev/null || true
  fi
  if [ -f "$PEERDIR/$peer_name-privatekey" ]; then
    mv "$PEERDIR/$peer_name-privatekey" "$ARCHIVE_DIR/" 2>/dev/null || true
  fi
  if [ -f "$PEERDIR/$peer_name-publickey" ]; then
    mv "$PEERDIR/$peer_name-publickey" "$ARCHIVE_DIR/" 2>/dev/null || true
  fi
  if [ -f "$PEERDIR/$peer_name.png" ]; then
    mv "$PEERDIR/$peer_name.png" "$ARCHIVE_DIR/" 2>/dev/null || true
  fi

  print_info "Peer removed from configuration"
  print_info "Files archived to: $ARCHIVE_DIR"
  print_info ""

  if [ "$INTERACTIVE_MODE" -eq 0 ]; then
    print_prompt "Restart WireGuard interface now? [y/N]: "
    read -r restart
    if [ "${restart##[Yy]}" = "" ]; then
      /etc/init.d/network reload
      print_info "Interface reloaded"
    else
      print_warn "Remember to restart the interface: /etc/init.d/network reload"
    fi
  fi
}

#
# FUNCTION: ENABLE
#
do_enable() {
  peer_name="$1"

  if [ -z "$peer_name" ]; then
    print_error "Peer name required"
    return 1
  fi

  # Find UCI section
  uci_section=""
  for section in $(uci show network 2>/dev/null | grep "=wireguard_${WG_IFACE}$" | cut -d. -f2 | cut -d= -f1); do
    desc=$(uci get network."$section".description 2>/dev/null || "")
    if [ "$desc" = "$peer_name" ]; then
      uci_section="$section"
      break
    fi
  done

  if [ -z "$uci_section" ]; then
    print_error "Peer '$peer_name' not found"
    return 1
  fi

  print_info "Enabling peer '$peer_name'..."
  uci delete network.$uci_section.disabled 2>/dev/null || true
  uci commit network

  print_info "Peer enabled"
  print_info ""

  if [ "$INTERACTIVE_MODE" -eq 0 ]; then
    print_prompt "Restart WireGuard interface now? [y/N]: "
    read -r restart
    if [ "${restart##[Yy]}" = "" ]; then
      /etc/init.d/network reload
      print_info "Interface reloaded"
    fi
  fi
}

#
# FUNCTION: DISABLE
#
do_disable() {
  peer_name="$1"

  if [ -z "$peer_name" ]; then
    print_error "Peer name required"
    return 1
  fi

  # Find UCI section
  uci_section=""
  for section in $(uci show network 2>/dev/null | grep "=wireguard_${WG_IFACE}$" | cut -d. -f2 | cut -d= -f1); do
    desc=$(uci get network."$section".description 2>/dev/null || "")
    if [ "$desc" = "$peer_name" ]; then
      uci_section="$section"
      break
    fi
  done

  if [ -z "$uci_section" ]; then
    print_error "Peer '$peer_name' not found"
    return 1
  fi

  print_info "Disabling peer '$peer_name'..."
  uci set network.$uci_section.disabled=1
  uci commit network

  print_info "Peer disabled (configuration preserved)"
  print_info ""

  if [ "$INTERACTIVE_MODE" -eq 0 ]; then
    print_prompt "Restart WireGuard interface now? [y/N]: "
    read -r restart
    if [ "${restart##[Yy]}" = "" ]; then
      /etc/init.d/network reload
      print_info "Interface reloaded"
    fi
  fi
}

#
# FUNCTION: TRAFFIC
#
do_traffic() {
  if ! wg show "$WG_IFACE" >/dev/null 2>&1; then
    print_error "WireGuard interface '$WG_IFACE' is not running"
    return 1
  fi

  print_info ""
  print_info "Traffic Statistics for '$WG_IFACE'"
  print_info "════════════════════════════════════════"
  print_info ""

  # Get peer list and match with traffic
  for section in $(uci show network 2>/dev/null | grep "=wireguard_${WG_IFACE}$" | cut -d. -f2 | cut -d= -f1); do
    desc=$(uci get network."$section".description 2>/dev/null || echo "$section")
    pubkey=$(uci get network."$section".public_key 2>/dev/null || echo "")

    if [ -n "$pubkey" ]; then
      # Get transfer data from wg show
      transfer=$(wg show "$WG_IFACE" dump | grep "$pubkey" | awk '{print "RX: "$6" bytes, TX: "$7" bytes"}' || echo "No data")

      print_info "  Peer: $desc"
      print_info "    $transfer"
      print_info ""
    fi
  done
}

#
# FUNCTION: ACTIVE
#
do_active() {
  if ! wg show "$WG_IFACE" >/dev/null 2>&1; then
    print_error "WireGuard interface '$WG_IFACE' is not running"
    return 1
  fi

  print_info ""
  print_info "Active Connections on '$WG_IFACE'"
  print_info "════════════════════════════════════════"
  print_info ""

  found=0
  for section in $(uci show network 2>/dev/null | grep "=wireguard_${WG_IFACE}$" | cut -d. -f2 | cut -d= -f1); do
    desc=$(uci get network."$section".description 2>/dev/null || echo "$section")
    pubkey=$(uci get network."$section".public_key 2>/dev/null || echo "")
    allowed=$(uci get network."$section".allowed_ips 2>/dev/null | head -n1 || echo "N/A")

    if [ -n "$pubkey" ]; then
      # Check if peer has recent handshake (within 3 minutes = 180 seconds)
      handshake_ago=$(wg show "$WG_IFACE" dump | grep "$pubkey" | awk '{print $5}' || echo "0")

      if [ "$handshake_ago" != "0" ] && [ -n "$handshake_ago" ] && [ "$handshake_ago" -lt 180 ]; then
        found=1
        endpoint=$(wg show "$WG_IFACE" dump | grep "$pubkey" | awk '{print $3":"$4}' || echo "N/A")

        print_info "  Peer: $desc"
        print_info "    IP:       $allowed"
        print_info "    Endpoint: $endpoint"
        print_info "    Last:     ${handshake_ago}s ago"
        print_info ""
      fi
    fi
  done

  if [ "$found" -eq 0 ]; then
    print_warn "  No active peers"
    print_info ""
  fi
}

#
# INTERACTIVE: Peer Management Submenu
#
interactive_manage_peer() {
  peer_name="$1"

  while true; do
    clear_screen

    # Check if peer is enabled or disabled
    uci_section=""
    for section in $(uci show network 2>/dev/null | grep "=wireguard_${WG_IFACE}$" | cut -d. -f2 | cut -d= -f1); do
      desc=$(uci get network."$section".description 2>/dev/null || "")
      if [ "$desc" = "$peer_name" ]; then
        uci_section="$section"
        break
      fi
    done

    enabled=$(uci get network."$uci_section".disabled 2>/dev/null || echo "0")

    print_info ""
    print_info "Manage Peer: $peer_name"
    print_info "════════════════════════════════════════"
    print_info "1. Show details + QR code"
    if [ "$enabled" = "1" ]; then
      print_info "2. Enable peer"
    else
      print_info "2. Disable peer"
    fi
    print_info "3. Remove peer"
    print_info "4. Back to main menu"
    print_info ""
    print_prompt "Select option [1-4]: "
    read -r choice

    case "$choice" in
      1)
        do_show "$peer_name"
        print_prompt "Press Enter to continue..."
        read -r dummy
        ;;
      2)
        if [ "$enabled" = "1" ]; then
          do_enable "$peer_name"
        else
          do_disable "$peer_name"
        fi
        print_prompt "Press Enter to continue..."
        read -r dummy
        ;;
      3)
        do_remove "$peer_name"
        return 0
        ;;
      4)
        return 0
        ;;
      *)
        print_error "Invalid option"
        ;;
    esac
  done
}

#
# INTERACTIVE: Peer Selection Submenu
#
interactive_select_peer() {
  clear_screen
  peer_list=$(do_list)

  if [ -z "$peer_list" ]; then
    print_warn "No peers configured. Add a peer first."
    print_prompt "Press Enter to continue..."
    read -r dummy
    return 1
  fi

  print_prompt "Select peer number (or 0 to cancel): "
  read -r peer_num

  if [ "$peer_num" = "0" ]; then
    return 0
  fi

  # Validate number
  if ! echo "$peer_num" | grep -qE '^[0-9]+$'; then
    print_error "Invalid selection"
    print_prompt "Press Enter to continue..."
    read -r dummy
    return 1
  fi

  # Find peer name by number
  selected_peer=$(echo "$peer_list" | grep "^$peer_num:" | cut -d: -f2)

  if [ -z "$selected_peer" ]; then
    print_error "Invalid peer number"
    print_prompt "Press Enter to continue..."
    read -r dummy
    return 1
  fi

  interactive_manage_peer "$selected_peer"
}

#
# INTERACTIVE: Main Menu
#
interactive_menu() {
  INTERACTIVE_MODE=1

  while true; do
    clear_screen

    print_info ""
    print_info "WireGuard Peer Management"
    print_info "════════════════════════════════════════"
    print_info "Interface: $WG_IFACE"
    print_info ""
    print_info "1. List all peers"
    print_info "2. Add new peer"
    print_info "3. Manage existing peer"
    print_info "4. Show traffic statistics"
    print_info "5. Show active connections"
    print_info "6. Restart WireGuard interface"
    print_info "7. Exit"
    print_info ""
    print_prompt "Select option [1-7]: "
    read -r choice

    case "$choice" in
      1)
        do_list
        print_prompt "Press Enter to continue..."
        read -r dummy
        ;;
      2)
        do_add
        print_prompt "Press Enter to continue..."
        read -r dummy
        ;;
      3)
        interactive_select_peer
        ;;
      4)
        do_traffic
        print_prompt "Press Enter to continue..."
        read -r dummy
        ;;
      5)
        do_active
        print_prompt "Press Enter to continue..."
        read -r dummy
        ;;
      6)
        print_info "Restarting WireGuard interface..."
        /etc/init.d/network reload
        print_info "Interface reloaded"
        print_prompt "Press Enter to continue..."
        read -r dummy
        ;;
      7)
        print_info "Goodbye!"
        exit 0
        ;;
      *)
        print_error "Invalid option. Please select 1-7."
        ;;
    esac
  done
}

#
# MAIN EXECUTION
#
if [ -z "$ACTION" ]; then
  # No action specified - enter interactive mode
  interactive_menu
else
  # Command-line mode
  case "$ACTION" in
    list)
      do_list
      ;;
    show)
      do_show "$PEER_NAME"
      ;;
    add)
      do_add
      ;;
    remove)
      do_remove "$PEER_NAME"
      ;;
    enable)
      do_enable "$PEER_NAME"
      ;;
    disable)
      do_disable "$PEER_NAME"
      ;;
    traffic)
      do_traffic
      ;;
    active)
      do_active
      ;;
  esac
fi
