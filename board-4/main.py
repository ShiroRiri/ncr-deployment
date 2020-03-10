import sys
import threading
import time
import board
import busio
import digitalio
import adafruit_ads1x15.ads1115 as ADS
import adafruit_rfm9x
from adafruit_ads1x15.analog_in import AnalogIn
from adafruit_ds18x20 import DS18X20
from adafruit_onewire.bus import OneWireBus
from bintools import DataLogWriter, FieldTypes

import paho.mqtt.publish as publish
import paho.mqtt.client as mqtt

MQTT_SERVER = "localhost"
#MQTT_SERVER = "192.168.4.1"
MQTT_PATH_COMMAND = "command_channel"
MQTT_PATH_REPLY = "reply_channel"

# command list
# 1. ONLINE
# 2. START DATA ACQUISITION
# 3. STOP DATA ACQUISITION
# 4. POWER OFF

def main():
    initialize_io()
    logging = False

    # Create logging threads
    stop_event = threading.Event()
    i2c_thread = threading.Thread(target = log_i2c_devices, name = 'i2c-logger', args = (stop_event, i2c_writer))
    ow_thread = threading.Thread(target = log_ow_devices, name = 'ow-logger', args = (stop_event, ow_writer))

    while True:
        client = mqtt.Client()
        client.on_connect = on_connect
        client.on_message = on_message
        client.connect(MQTT_SERVER, 1883, 60)

        # Await packet on channel 42 (the answer to life, universe, and everything)
        packet = radio.receive(timeout = None, keep_listening = True, rx_filter = 42)
        if data is "NCR-START".encode("utf8"):
            i2c_thread.start()
            ow_thread.start()
            logging = True
            publish.single(MQTT_PATH_COMMAND, "START", hostname=MQTT_SERVER)
        elif data is "NCR-STOP".encode("utf8"):
            stop_event.set()
            logging = False
            publish.single(MQTT_PATH_COMMAND, "STOP", hostname=MQTT_SERVER)
        elif data is "NCR-OFF".encode("utf8"):
            # TODO: Send running status to requestor
            publish.single(MQTT_PATH_COMMAND, "OFF", hostname=MQTT_SERVER)
        elif data is not None:
            print("Unhandled radio packet: {}\n".format(data))

        #    client.loop_forever()

def initialize_io():
    try:
        i2c = busio.I2C(board.SCL, board.SDA)
        spi = busio.SPI(board.SCK, MOSI=board.MOSI, MISO=board.MISO)
        ow_bus = OneWireBus(board.D4)

        # Initialize devices
        global adc, radio, temp_sensor, sg_enable

        adc = ADS.ADS1115(i2c)

        radio_cs = digitalio.DigitalInOut(board.D5)
        radio_reset = digitalio.DigitalInOut(board.D6p)
        radio = adafruit_rfm9x.RFM9x(spi, radio_cs, radio_reset, 433.0)
        radio.enable_crc = True

        temp_sensor = DS18X20(ow_bus, ow_bus.scan()[0])
        temp_sensor.resolution = 9 # Speeds up the polling rate while sacrificing some resolution

        sg_enable = digitalio.DigitalInOut(D17)
        sg_enable.direction = digitalio.Direction.OUTPUT
        sg_enable.value = False

        print("IO successfully initialized")

    except Exception as e:
        print("Error while initializing IO - {}\n".format(e))
        sys.exit(1)

def log_i2c_devices(stop_event):
    sg_enable.value = True # Enable strain guage before ADC samples
    adc.mode = ADS.Mode.CONTINUOUS # Enter continuous capture mode for improved performance

    writer = DataLogWriter("~/i2c-{}.bin".format(time.strftime("%d-%m-%H:%M:%S")), [{'name': 'StrainGuage', 'type': FieldTypes.FLOAT}])
    while not stop_event.is_set():
        writer.beginSample()
        writer.log(AnalogIn(adc, 0, 1).voltage)
        writer.endSample()

    # Enter power-saving mode on ADC
    adc.mode = ADS.Mode.SINGLE
    AnalogIn(adc, 0, 1)

    writer.close()

def log_ow_devices(stop_event, writer):
    writer = DataLogWriter("~/ow-{}.bin".format(time.strftime("%d-%m-%H:%M:%S")), [{'name': 'TempProbe', 'type': FieldTypes.FLOAT}])
    while not stop_event.is_set():
        writer.beginSample()
        writer.log(temp_sensor.temperature())
        writer.endSample()

    writer.close()

def on_connect(client, userdata, flags, rc):
        print("Connected to client with result code " +str(rc))
        client.subscribe(MQTT_PATH_REPLY)
        publish.single(MQTT_PATH_COMMAND, "ONLINE", hostname=MQTT_SERVER)
#        client.publish(MQTT_PATH_COMMAND, "ONLINE")

def on_message(client, userdata, msg):
        print(msg.topic+" "+str(msg.payload))

# If script is directly called, start main
if __name__ == "__main__":
    main()
