#!/usr/bin/env bash
set -euo pipefail

# Raspberry Pi Static IP Configuration Script
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
    printf "%-15s %-12s %-12s %-18s\n" "INTERFACE" "TYPE" "STATUS" "IP ADDRESS"
    printf "%-15s %-12s %-12s %-18s\n" "---------" "----" "------" "----------"

    if [[ "$net_mgr" == "networkmanager" ]]; then
        nmcli -t -f DEVICE,TYPE,STATE device | while IFS=: read -r dev type state; do
            local ip_addr
            ip_addr=$(ip -4 -o addr show "$dev" 2>/dev/null | awk '{print $4}' | head -n1) || true
            [[ -z "$ip_addr" ]] && ip_addr="--"
            printf "%-15s %-12s %-12s %-18s\n" "$dev" "$type" "$state" "$ip_addr"
        done
    else
        # For dhcpcd, use ip command
        ip -o link show | awk '{print $2}' | sed 's/://' | while read -r dev; do
            local state="unknown"
            local type="ethernet"

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

            local ip_addr
            ip_addr=$(ip -4 -o addr show "$dev" 2>/dev/null | awk '{print $4}' | head -n1) || true
            [[ -z "$ip_addr" ]] && ip_addr="--"

            # Skip loopback
            [[ "$dev" == "lo" ]] && continue

            printf "%-15s %-12s %-12s %-18s\n" "$dev" "$type" "$state" "$ip_addr"
        done
    fi
    echo ""
}

# Validate IP address format
validate_ip() {
    local ip="$1"
    # Remove CIDR notation if present
    local ip_only="${ip%%/*}"

    if [[ $ip_only =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local IFS='.'
        local -a octets=($ip_only)
        for octet in "${octets[@]}"; do
            ((octet > 255)) && return 1
        done
        return 0
    fi
    return 1
}

# Configure interface using NetworkManager
configure_networkmanager() {
    local iface="$1"
    local static_ip="$2"
    local gateway="$3"
    local dns1="$4"
    local type="$5"

    local con_name
    con_name=$(nmcli -t -f NAME,DEVICE connection show | awk -F: -v d="$iface" '$2==d {print $1}')

    if [[ -z "$con_name" ]]; then
        echo -e "${YELLOW}No connection found for $iface. Creating one...${NC}"
        con_name="${type}-${iface}"
        nmcli connection add type "$type" ifname "$iface" con-name "$con_name" \
            ipv4.method manual ipv4.address "$static_ip" ipv4.gateway "$gateway" ipv4.dns "$dns1"
    else
        echo -e "${YELLOW}Modifying existing connection: $con_name${NC}"
        nmcli connection modify "$con_name" ipv4.addresses "$static_ip"
        nmcli connection modify "$con_name" ipv4.gateway "$gateway"
        nmcli connection modify "$con_name" ipv4.method manual
        nmcli connection modify "$con_name" ipv4.dns "$dns1"
    fi

    # Restart connection
    echo "Activating connection..."
    nmcli connection down "$con_name" 2>/dev/null || true
    nmcli connection up "$con_name"
}

# Configure interface using dhcpcd
configure_dhcpcd() {
    local iface="$1"
    local static_ip="$2"
    local gateway="$3"
    local dns1="$4"

    # Remove CIDR notation for dhcpcd config
    local ip_only="${static_ip%%/*}"
    local netmask="${static_ip##*/}"

    # Convert CIDR to netmask if needed
    if [[ "$netmask" == "24" ]]; then
        netmask="255.255.255.0"
    elif [[ "$netmask" == "16" ]]; then
        netmask="255.255.0.0"
    elif [[ "$netmask" == "8" ]]; then
        netmask="255.0.0.0"
    fi

    echo -e "${YELLOW}Configuring $iface in /etc/dhcpcd.conf${NC}"

    # Backup dhcpcd.conf
    sudo cp /etc/dhcpcd.conf /etc/dhcpcd.conf.backup."$(date +%Y%m%d_%H%M%S)"

    # Remove existing configuration for this interface
    sudo sed -i "/^interface $iface/,/^$/d" /etc/dhcpcd.conf

    # Add new configuration
    cat << EOF | sudo tee -a /etc/dhcpcd.conf > /dev/null

interface $iface
static ip_address=$static_ip
static routers=$gateway
static domain_name_servers=$dns1
EOF

    echo -e "${GREEN}Configuration added to /etc/dhcpcd.conf${NC}"
    echo "Restarting dhcpcd service..."
    sudo systemctl restart dhcpcd
}

# Configure a single interface
configure_iface() {
    local iface="$1"
    local type="$2"
    local net_mgr="$3"

    echo ""
    echo -e "${GREEN}Detected interface ($type): $iface${NC}"

    # Get and validate static IP
    local static_ip
    while true; do
        read -rp "Enter static IP (e.g., 192.168.0.50/24): " static_ip

        if [[ -z "$static_ip" ]]; then
            echo -e "${RED}Error: IP address cannot be empty${NC}"
            continue
        fi

        # Add /24 netmask if user didn't include it
        if [[ ! "$static_ip" =~ / ]]; then
            echo -e "${YELLOW}No netmask specified, using /24 by default${NC}"
            static_ip="${static_ip}/24"
        fi

        if validate_ip "$static_ip"; then
            break
        else
            echo -e "${RED}Error: Invalid IP address format${NC}"
        fi
    done

    # Get and validate gateway
    local gateway
    while true; do
        read -rp "Enter gateway (e.g., 192.168.0.1): " gateway

        if [[ -z "$gateway" ]]; then
            echo -e "${RED}Error: Gateway cannot be empty${NC}"
            continue
        fi

        if validate_ip "$gateway"; then
            break
        else
            echo -e "${RED}Error: Invalid gateway format${NC}"
        fi
    done

    # Get DNS or use gateway as default
    local dns1
    read -rp "Enter primary DNS (e.g., 192.168.0.1) [Press Enter to use gateway]: " dns1

    if [[ -z "$dns1" ]]; then
        dns1="$gateway"
        echo -e "${YELLOW}Using gateway as DNS: $dns1${NC}"
    elif ! validate_ip "$dns1"; then
        echo -e "${YELLOW}Warning: Invalid DNS format, using gateway instead${NC}"
        dns1="$gateway"
    fi

    # Configure based on network manager
    if [[ "$net_mgr" == "networkmanager" ]]; then
        configure_networkmanager "$iface" "$static_ip" "$gateway" "$dns1" "$type"
    else
        configure_dhcpcd "$iface" "$static_ip" "$gateway" "$dns1"
    fi

    echo -e "${GREEN}Configuration applied successfully!${NC}"
}

# Main script
echo -e "${GREEN}=== Raspberry Pi Static IP Configuration ===${NC}"
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

# Configure wired interfaces
for iface in "${wired_ifaces[@]}"; do
    configure_iface "$iface" "ethernet" "$NET_MGR"
done

# Configure Wi-Fi interfaces - with warning
for iface in "${wifi_ifaces[@]}"; do
    echo -e "${YELLOW}Warning: Configuring WiFi interface $iface${NC}"
    echo "This will modify the network configuration for this interface only."
    echo "Other WiFi connections and auto-connect features will not be affected."
    read -rp "Do you want to continue? (y/n): " confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        configure_iface "$iface" "wifi" "$NET_MGR"
    else
        echo "Skipping $iface"
    fi
done

echo ""
show_network_config "Final Configuration" "$NET_MGR"
echo -e "${GREEN}Done.${NC}"
