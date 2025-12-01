#!/usr/bin/env bash
set -euo pipefail

# Raspberry Pi DHCP Configuration Script
# Supports both NetworkManager (modern Raspberry Pi OS) and dhcpcd (legacy)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect network management system
detect_network_manager() {
    if command -v nmcli &> /dev/null && systemctl is-active --quiet NetworkManager; then
        echo "networkmanager"
    elif systemctl is-active --quiet dhcpcd; then
        echo "dhcpcd"
    else
        echo "unknown"
    fi
}

# Display network configuration in a table format
show_network_config() {
    local title="$1"
    local net_mgr="$2"

    echo -e "${GREEN}=== $title ===${NC}"
    printf "%-15s %-12s %-12s %-18s %-12s\n" "INTERFACE" "TYPE" "STATUS" "IP ADDRESS" "METHOD"
    printf "%-15s %-12s %-12s %-18s %-12s\n" "---------" "----" "------" "----------" "------"

    if [[ "$net_mgr" == "networkmanager" ]]; then
        nmcli -t -f DEVICE,TYPE,STATE device | while IFS=: read -r dev type state; do
            local ip_addr method
            ip_addr=$(ip -4 -o addr show "$dev" 2>/dev/null | awk '{print $4}' | head -n1) || true
            [[ -z "$ip_addr" ]] && ip_addr="--"

            # Get IP method (auto/manual)
            local con_name
            con_name=$(nmcli -t -f NAME,DEVICE connection show | awk -F: -v d="$dev" '$2==d {print $1}')
            if [[ -n "$con_name" ]]; then
                method=$(nmcli -t -f ipv4.method connection show "$con_name" | cut -d: -f2)
            else
                method="--"
            fi

            printf "%-15s %-12s %-12s %-18s %-12s\n" "$dev" "$type" "$state" "$ip_addr" "$method"
        done
    else
        # For dhcpcd, use ip command
        ip -o link show | awk '{print $2}' | sed 's/://' | while read -r dev; do
            local state="unknown"
            local type="ethernet"
            local method="dhcp"

            # Determine type
            if [[ "$dev" =~ ^wlan ]]; then
                type="wifi"
            fi

            # Check if interface is up
            if ip link show "$dev" | grep -q "state UP"; then
                state="connected"
            else
                state="disconnected"
            fi

            # Check if interface has static IP config in dhcpcd.conf
            if grep -q "^interface $dev" /etc/dhcpcd.conf 2>/dev/null; then
                method="static"
            fi

            local ip_addr
            ip_addr=$(ip -4 -o addr show "$dev" 2>/dev/null | awk '{print $4}' | head -n1) || true
            [[ -z "$ip_addr" ]] && ip_addr="--"

            # Skip loopback
            [[ "$dev" == "lo" ]] && continue

            printf "%-15s %-12s %-12s %-18s %-12s\n" "$dev" "$type" "$state" "$ip_addr" "$method"
        done
    fi
    echo ""
}

# Configure interface to use DHCP with NetworkManager
configure_networkmanager_dhcp() {
    local iface="$1"
    local type="$2"

    local con_name
    con_name=$(nmcli -t -f NAME,DEVICE connection show | awk -F: -v d="$iface" '$2==d {print $1}')

    if [[ -z "$con_name" ]]; then
        echo -e "${YELLOW}No connection found for $iface. Creating one...${NC}"
        con_name="${type}-${iface}"
        nmcli connection add type "$type" ifname "$iface" con-name "$con_name" \
            ipv4.method auto
    else
        echo -e "${YELLOW}Modifying existing connection: $con_name${NC}"

        # Clear any static IP configuration (order matters: method first, then clear properties)
        nmcli connection modify "$con_name" ipv4.method auto
        nmcli connection modify "$con_name" ipv4.gateway ""
        nmcli connection modify "$con_name" ipv4.dns ""
        nmcli connection modify "$con_name" ipv4.addresses ""
    fi

    # Restart connection
    echo "Activating connection..."
    nmcli connection down "$con_name" 2>/dev/null || true
    nmcli connection up "$con_name"
}

# Configure interface to use DHCP with dhcpcd
configure_dhcpcd_dhcp() {
    local iface="$1"

    echo -e "${YELLOW}Removing static configuration for $iface in /etc/dhcpcd.conf${NC}"

    # Check if interface has static config
    if grep -q "^interface $iface" /etc/dhcpcd.conf 2>/dev/null; then
        # Backup dhcpcd.conf
        sudo cp /etc/dhcpcd.conf /etc/dhcpcd.conf.backup."$(date +%Y%m%d_%H%M%S)"

        # Remove static configuration for this interface
        # This removes from "interface $iface" line until the next empty line
        sudo sed -i "/^interface $iface/,/^$/d" /etc/dhcpcd.conf

        echo -e "${GREEN}Static configuration removed from /etc/dhcpcd.conf${NC}"
        echo "Restarting dhcpcd service..."
        sudo systemctl restart dhcpcd

        # Force DHCP renewal
        echo "Requesting new DHCP lease..."
        sudo dhcpcd -n "$iface" 2>/dev/null || true
    else
        echo -e "${GREEN}Interface $iface is already using DHCP${NC}"
    fi
}

# Configure a single interface for DHCP
configure_iface_dhcp() {
    local iface="$1"
    local type="$2"
    local net_mgr="$3"

    echo ""
    echo -e "${GREEN}Configuring interface ($type): $iface${NC}"

    # Configure based on network manager
    if [[ "$net_mgr" == "networkmanager" ]]; then
        configure_networkmanager_dhcp "$iface" "$type"
    else
        configure_dhcpcd_dhcp "$iface"
    fi

    echo -e "${GREEN}DHCP configuration applied successfully!${NC}"
}

# Main script
echo -e "${GREEN}=== Raspberry Pi DHCP Configuration ===${NC}"
echo ""

# Detect network management system
NET_MGR=$(detect_network_manager)

if [[ "$NET_MGR" == "unknown" ]]; then
    echo -e "${RED}Error: Could not detect network management system${NC}"
    echo "Neither NetworkManager nor dhcpcd appears to be running."
    exit 1
fi

echo -e "${YELLOW}Detected network manager: $NET_MGR${NC}"
echo ""

show_network_config "Current Network Configuration" "$NET_MGR"

# Detect connected interfaces
if [[ "$NET_MGR" == "networkmanager" ]]; then
    mapfile -t wired_ifaces < <(nmcli device status | awk '$2=="ethernet" && $3=="connected" {print $1}')
    mapfile -t wifi_ifaces < <(nmcli device status | awk '$2=="wifi" && $3=="connected" {print $1}')
else
    # For dhcpcd, detect interfaces manually
    mapfile -t wired_ifaces < <(ip -o link show | awk '{print $2}' | sed 's/://' | grep -E '^eth|^enp' || true)
    mapfile -t wifi_ifaces < <(ip -o link show | awk '{print $2}' | sed 's/://' | grep -E '^wlan' || true)
fi

# Check if there are any interfaces
if [[ ${#wired_ifaces[@]} -eq 0 && ${#wifi_ifaces[@]} -eq 0 ]]; then
    echo -e "${RED}No interfaces found. Please check your network connections.${NC}"
    exit 1
fi

# Ask user which interfaces to configure
echo -e "${YELLOW}This script will configure selected interfaces to use DHCP (automatic IP assignment).${NC}"
echo "Any existing static IP configuration will be removed."
echo ""

# Configure wired interfaces
for iface in "${wired_ifaces[@]}"; do
    echo "Found wired interface: $iface"
    read -rp "Configure $iface for DHCP? (y/n): " confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        configure_iface_dhcp "$iface" "ethernet" "$NET_MGR"
    else
        echo "Skipping $iface"
    fi
done

# Configure Wi-Fi interfaces
for iface in "${wifi_ifaces[@]}"; do
    echo -e "${YELLOW}Warning: Found WiFi interface $iface${NC}"
    echo "This will modify the network configuration for this interface only."
    echo "Other WiFi connections and auto-connect features will not be affected."
    read -rp "Configure $iface for DHCP? (y/n): " confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        configure_iface_dhcp "$iface" "wifi" "$NET_MGR"
    else
        echo "Skipping $iface"
    fi
done

echo ""
echo -e "${YELLOW}Waiting for network to stabilize...${NC}"
sleep 3

show_network_config "Final Configuration" "$NET_MGR"
echo -e "${GREEN}Done.${NC}"
