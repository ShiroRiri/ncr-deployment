#!/bin/bash
if [ "$EUID" -ne 0 ]; then
  echo "Run this script as root: sudo bash pi-setup.sh"
  exit
fi

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

# Format USB Stick & create mount point
umount /dev/sda1 # Just in case it's pre-mounted
mkfs.exfat /dev/sda1
mkdir -p /mnt/usb
echo "/dev/sda1 /mnt/usb exfat gid=1000,uid=1000 0 0" >> /etc/fstab

# --- Default Configurations ---
echo "Enabling default configs..."
raspi-config nonint do_overscan 1
raspi-config nonint do_ssh 0
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
  echo "# I2C Clock Stretch" >> /boot/config.txt
  echo "dtparam=i2c_arm_baudrate=10000" >> /boot/config.txt
fi

# Copy repo over to /etc
echo "Installing files to root filesystem..."
mkdir -p /usr/ncr-deployment &&
cp -vr ./* /usr/ncr-deployment/

# Create bootstrap service
echo "Creating bootstrap service..."
printf "
[Unit]
Description=NCR Bootstrap Service
After=network.Target
StartLimitIntervalSec=0

[Service]
Type=simple
RestartSec=5
User=pi
ExecStart=/usr/bin/python3 /usr/ncr-deployment/$main_dir/main.py

[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/ncr-bootstrap.service

/bin/systemctl enable ncr-bootstrap

echo "Done! Rebooting..."
reboot
