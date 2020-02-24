import sys
import threading
import board
import busio
import digitalio
import adafruit_ads1x15.ads1115 as ADS
from adafruit_ads1x15.analog_in import AnalogIn
from adafruit_ds18x20 import DS18X20
from adafruit_onewire.bus import OneWireBus
import adafruit_rfm9x
from bintools import DataLogWriter, FieldTypes

# If script is directly called, start main
if __name__ == "__main__":
    main()

def main():
    initialize_io()
    logging = False

    # Create logfiles
    i2c_writer = DataLogWriter('~/i2c-log.bin', [{'name': 'StrainGuage', 'type': FieldTypes.FLOAT}])
    ow_writer = DataLogWriter('~/ow-log.bin', [{'name': 'TempProbe', 'type': FieldTypes.FLOAT}])

    # Create logging threads
    stop_event = threading.Event()
    i2c_thread = threading.Thread(target = log_i2c_devices, name = 'i2c-logger', args = (stop_event, i2c_writer))
    ow_thread = threading.Thread(target = log_ow_devices, name = 'ow-logger', args = (stop_event, ow_writer))

    while True:
        # Await packet on channel 42 (the answer to life, universe, and everything)
        packet = radio.receive(timeout = None, keep_listening = True, rx_filter = 42)
        if data is "NCR-START".encode("utf8"):
            i2c_thread.start()
            ow_thread.start()
            logging = True
        elif data is "NCR-STOP".encode("utf8"):
            stop_event.set()
            logging = False
        elif data is "NCR-QUERY".encode("utf8"):
            # TODO: Send running status to requestor
        else:
            print("Unhandled radio packet: {}\n".format(data))

def initialize_io():
    try:
        i2c = busio.I2C(board.SCL, board.SDA)
        spi = busio.SPI(board.SCK, MOSI=board.MOSI, MISO=board.MISO)
        ow_bus = OneWireBus(board.D4)

        # Initialize devices
        global adc, radio, temp_sensor, sg_enable

        adc = ADS.ADS1115(i2c)

        radio_cs = digitalio.DigitalInOut(board.D7)
        radio_reset = digitalio.DigitalInOut(board.D25)
        radio = adafruit_rfm9x.RFM9x(spi, radio_cs, radio_reset, 433.0)
        radio.enable_crc = True

        temp_sensor = DS18X20(ow_bus, ow_bus.scan()[0])
        temp_sensor.resolution = 9 # Speeds up the polling rate while sacrificing some resolution

        sg_enable = digitalio.DigitalInOut(D17)
        sg_enable.direction = digitalio.Direction.OUTPUT
        sg_enable.value = False

        print("IO successfully initialized")

    except Exception as e:
        print("Error while initializing IO - {}\n".format(e.message))
        sys.exit(1)

def log_i2c_devices(stop_event, writer):
    sg_enable.value = True # Enable strain guage before ADC samples

    while not stop_event.is_set():
        writer.beginSample()
        writer.log(AnalogIn(adc, 0, 1).voltage)
        writer.endSample()

def log_ow_devices(stop_event, writer):
    while not stop_event.is_set():
        writer.beginSample()
        writer.log(temp_sensor.temperature())
        writer.endSample()
