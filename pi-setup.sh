#!/bin/bash
if [ "$EUID" -ne 0 ]; then
  echo "Run this script as root: sudo bash pi-setup.sh"
  exit
fi

# --- Board Select ---
BOARD=$(whiptail --backtitle "NCR Pi Setup" \
  --menu "Select configuration" 15 60 4 \
  "RPi-1" "BNO055, MMA8451, TCA9548A" \
  "RPi-2" "DS18B20, ADS1115, Strain Guages" \
  "RPi-3" "BMP388, BME280, SGP30" \
  "RPi-4 [Zero]" "RFM96W, DS18B20, ADS1115, Strain Guage" 3>&1 1>&2 2>&3)

case $BOARD in
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
apt update &&
apt upgrade -y

# --- Package Install ---
echo "Installing required packages..."
apt install -y python3-pip

# --- Python Dependency Install ---
echo "Installing python dependencies..."
pip3 -r $main_dir/requirements.txt

# --- Default Configurations ---
echo "Enabling default configs..."
raspi-config nonint do_overscan 0
raspi-config nonint do_ssh 1

# --- Board Specific Configurations ---
echo "Enabling board-specific configs..."

if "$spi"; then
  raspi-config noint do_spi 1
fi

if "$i2c"; then
  raspi-config noint do_i2c 1
fi

if "$onewire"; then
  raspi-config noint do_onewire 1
fi

if "$i2c_clock_stretch"; then
  echo "dtparam=i2c_arm_baudrate=10000" >> /boot/config
fi

echo "Done!"
