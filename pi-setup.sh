#!/bin/bash
if [ "$EUID" -ne 0 ]; then
  echo "Run this script as root: sudo bash pi-setup.sh"
  exit
fi

# --- Board Select ---
board=$(whiptail --backtitle "NCR Pi Setup" \
  --menu "Select configuration" 15 60 4 \
  "RPi-1" "BNO055, MMA8451, TCA9548A" \
  "RPi-2" "DS18B20, ADS1115, Strain Guages" \
  "RPi-3" "BMP388, BME280, SGP30" \
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

source $main_dir/config.txt # Load configuration

# --- Package Update ---
echo "Updating packages...."
apt update -qq &&
apt upgrade -y -qq

# --- Package Install ---
echo "Installing required packages..."
apt install -y python3-pip git -qq

# --- Python Dependency Install ---
echo "Installing python dependencies..."
pip3 install -r $main_dir/requirements.txt -q

# --- Default Configurations ---
echo "Enabling default configs..."
raspi-config nonint do_overscan 1
raspi-config nonint do_ssh 0
echo -n $friendly_name > /etc/hostname

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
  sed -r "s/dtparam=i2c_arm=on/dtparam=i2c_arm=on\ndtparam=i2c_arm_baudrate=10000" /boot/config.txt
fi

echo "Done! Rebooting..."
reboot
