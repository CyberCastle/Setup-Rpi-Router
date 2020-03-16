#!/bin/bash

#############################################################
#### Building an Access Point/Router with a Raspberry Pi ####
#############################################################
# Logic this script based in this article: https://snikt.net/blog/2019/06/22/building-an-lte-access-point-with-a-raspberry-pi/
# Info for appply color to this script, obtained from here: http://www.andrewnoske.com/wiki/Bash_-_adding_color

## NOTE: Run this script as root user, example sudo ./setup-rpi-router.sh

# <<<--- Begin Error Handler --->>> #
# Piece of code obtain from here: https://gist.github.com/ahendrix/7030300

# Setting errtrace allows our ERR trap handler to be propagated to functions,
# expansions and subshells
set -o errtrace

# Trap ERR to provide an error handler whenever a command exits nonzero
# this is a more verbose version of set -o errexit
trap 'stackTrace' ERR

# Stack trace function
function stackTrace() {
  local err=$?
  set +o xtrace
  local code="${1:-1}"
  echo "Error in ${BASH_SOURCE[1]}:${BASH_LINENO[0]}. '${BASH_COMMAND}' exited with status $err"
  # Print out the stack trace described by $function_stack  
  if [ ${#FUNCNAME[@]} -gt 2 ]
  then
    echo "Call tree:"
    for ((i=1;i<${#FUNCNAME[@]}-1;i++))
    do
      echo " $i: ${BASH_SOURCE[$i+1]}:${BASH_LINENO[$i]} ${FUNCNAME[$i]}(...)"
    done
  fi
  exit "${code}"
}
#  <<<--- End Error Handler --->>>  #

# Make sure only root can run this script
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root." 1>&2
   exit 1
fi

printf "\n\e[36;1mUpdating System...\e[0m\n"
apt update
apt dist-upgrade -y

printf "\n\e[36;1mRemoving rfkill...\e[0m\n"
rfkill unblock wifi
apt purge -y  rfkill

printf "\n\e[36;1mInstalling the necessary packages...\e[0m\n"
apt install -y bridge-utils dnsmasq hostapd iptables iptables-persistent

printf "\n\e[36;1mSetting the network interfaces ...\e[0m\n"
if [[ -d /etc/network/interfaces ]]; then
  mv /etc/network/interfaces /etc/network/interfaces.bak
fi
cat <<EOT > /etc/network/interfaces
# Include files from /etc/network/interfaces.d:
source-directory /etc/network/interfaces.d

# Automatically connect the wired interface
auto eth0
allow-hotplug eth0
iface eth0 inet manual

# Automatically connect the wireless interface
auto wlan0
allow-hotplug wlan0
iface wlan0 inet manual

# Automatically connect the 3G/4G modem
auto eth1
allow-hotplug eth1
iface eth1 inet dhcp

# Create a bridge with both wired and wireless interfaces
auto br0
iface br0 inet static
        address 192.168.111.254
        netmask 255.255.255.0
        bridge_ports eth0 wlan0
        bridge_fd 0
        bridge_stp off
EOT

# Enable AC wireless mode
iw reg set US

printf "\n\e[36;1mSetting dnsmasq...\e[0m\n"
if [[ -d /etc/dnsmasq.conf ]]; then
  mv /etc/dnsmasq.conf /etc/dnsmasq.conf.bak
fi
cat <<EOT > /etc/dnsmasq.conf
# With tips obtained from here: https://pimylifeup.com/raspberry-pi-dns-server/

# Basic settings
domain-needed
bogus-priv
no-resolv

# Which network interface to use
interface=br0

# Which dhcp IP-range to use for dynamic IP-adresses
dhcp-range=192.168.111.50,192.168.111.150,24h

# Setting upstream DNS address
server=8.8.8.8
server=8.8.4.4
cache-size=1000
EOT

printf "\n\e[36;1mSetting hostapd...\e[0m\n"
# Setting default country
echo "country=US" >> /etc/wpa_supplicant/wpa_supplicant.conf
echo "denyinterfaces wlan0 eth0" >> /etc/dhcpcd.conf
if [[ -d /etc/hostapd/hostapd.conf ]]; then
  mv /etc/hostapd/hostapd.conf /etc/hostapd/hostapd.conf.bak
fi
cat <<EOT > /etc/hostapd/hostapd.conf
bridge=br0

interface=wlan0
driver=nl80211
ssid=Rpi-AP-Router

hw_mode=a
channel=36
ieee80211d=0
ieee80211h=0
ieee80211ac=0
ieee80211n=1
require_ht=1
ht_capab=[HT40+][SHORT-GI-20][SHORT-GI-40][DSSS_CCK-40]
obss_interval=5
wmm_enabled=1
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
country_code=US

wpa=2
auth_algs=1
wpa_passphrase=change_me!!!!
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOT
echo "DAEMON_CONF=\"/etc/hostapd/hostapd.conf\"" >> /etc/default/hostapd

printf "\n\e[36;1mEnabling services...\e[0m\n"
systemctl unmask dnsmasq
systemctl enable dnsmasq
systemctl unmask hostapd
systemctl enable hostapd

printf "\n\e[36;1mSetting iptables...\e[0m\n"
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf

iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp -m state --state NEW -m tcp --dport 53 -j ACCEPT
iptables -A INPUT -m pkttype --pkt-type multicast -j ACCEPT
iptables -A FORWARD -i eth0 -o eth1 -j ACCEPT
iptables -A FORWARD -i wlan0 -o eth1 -j ACCEPT
iptables -A POSTROUTING -t nat -o eth1 -j MASQUERADE
iptables-save > /etc/iptables/rules.v4

printf "\n\e[91;1mRebooting in 5 seconds...\e[0m\n"
sleep 5
reboot
