#!/bin/bash
if [ "$EUID" -ne 0 ]; then
  echo "Run this script as root: sudo bash pi-setup.sh"
  exit
fi

set -eo pipefail

# --- USB Erase Warning ---
whiptail --backtitle "NCR Pi Setup" --msgbox \
"WARNING: THIS SCRIPT WILL ERASE ALL DATA ON THE USB
PLUGGED INTO THE RASPBERRY PI. ENSURE ALL IMPORTANT DATA
IS BACKED UP. JOSH IS NOT RESPONSIBLE FOR ACCIDENTALLY
DELETING YOUR TERM PAPERS." 15 60

# --- Board Select ---
board=$(whiptail --backtitle "NCR Pi Setup"                               \
  --menu "Select configuration" 15 60 4                                   \
  "RPi-1" "BNO055, MMA8451, TCA9548A"                                     \
  "RPi-2" "DS18B20, ADS1115, Strain Guages"                               \
  "RPi-3" "BMP388, BME280, SGP30"                                         \
  "RPi-4 [Zero]" "RFM96W, DS18B20, ADS1115, Strain Guage" 3>&1 1>&2 2>&3)

case $board in
  "RPi-1")
    main_dir="board-1"
  ;;
  "RPi-2")
    main_dir="board-2"
  ;;
  "RPi-3")
    main_dir="board-3"
  ;;
  "RPi-4 [Zero]")
    main_dir="board-4"
  ;;
esac

source default/config.txt # Load default configuration
source $main_dir/config.txt # Load specific configuration

# --- Package Update ---
echo "Updating packages...."
apt update -qq &&
apt upgrade -y -qq

# --- Package Install ---
echo "Installing required packages..."
apt install -y $packages -qq

# --- Default Dependency Install ---
echo "Installing default dependencies..."
pip3 install -r default/requirements.txt -q

# --- Dependency Install ---
echo "Installing dependencies..."
pip3 install -r $main_dir/requirements.txt -q

# --- ncr-binary Install ---
git clone https://github.com/ShiroRiri/ncr-binary.git /tmp/ncr-binary
python3 /tmp/ncr-binary/setup.py install

# --- Format USB Stick & create mount point ---
umount /dev/sda1 || true # Just in case it's pre-mounted
fdisk /dev/sda <<EOF
g
n
1


t
11
w
EOF
mkfs.exfat /dev/sda1
mkdir -p /mnt/usb
echo "/dev/sda1 /mnt/usb exfat gid=1000,uid=1000 0 0" >> /etc/fstab

# --- Default Configurations ---
echo "Enabling default configs..."
raspi-config nonint do_overscan 1
raspi-config nonint do_ssh 0
raspi-config nonint do_wifi_country US
echo -n $friendly_name.local > /etc/hostname

# --- Board Specific Configurations ---
echo "Enabling board-specific configs..."

if "$spi"; then
  raspi-config nonint do_spi 0
fi

if "$i2c"; then
  raspi-config nonint do_i2c 0
fi

if "$onewire"; then
  raspi-config nonint do_onewire 0
fi

if "$i2c_clock_stretch"; then
  printf \
"[all]
# I2C Clock Stretch
dtparam=i2c_arm_baudrate=10000" >> /boot/config.txt
fi

if "$wifi_ap"; then
  printf \
"interface wlan0
    static ip_address=192.168.4.1/24
    nohook wpa_supplicant" >> /etc/dhcpcd.conf
    
  printf \
"interface=wlan0
dhcp-range=192.168.4.2,192.168.4.200,255.255.255.0,72h" > /etc/dnsmasq.conf

  printf \
"interface=wlan0
driver=nl80211
ssid=NCRocket-Net
hw_mode=g
channel=11
wmm_enabled=0
macaddr_acl=0
ignore_broadcast_ssid=0" > /etc/hostapd/hostapd.conf

  printf "DAEMON_CONF=\"/etc/hostapd/hostapd.conf\"" >> /etc/default/hostapd
  
  /bin/systemctl enable dnsmasq
  /bin/systemctl unmask hostapd
  /bin/systemctl enable hostapd
else
  raspi-config nonint do_wifi_ssid_passphrase NCRocket-Net
fi

# --- Copy repo over to /usr/share ---
echo "Installing files to root filesystem..."
mkdir -p /usr/share/ncr-deployment
cp -r ./* /usr/share/ncr-deployment/

# --- Create bootstrap service ---
echo "Creating bootstrap service..."
printf \
"[Unit]
Description=NCR Bootstrap Service
After=network.Target
StartLimitIntervalSec=0

[Service]
Type=simple
RestartSec=0
User=pi
ExecStart=/usr/bin/python3 /usr/share/ncr-deployment/$main_dir/main.py

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/ncr-bootstrap.service
/bin/systemctl enable ncr-bootstrap

echo "Done! Rebooting..."
reboot
