import asyncio
import board
import busio
import digitalio
import adafruit_rfm9x

PORT = 8000
VERSION = "1.0"
TRIGGER_MSG = "NCR-TRIGGER".encode("utf8")
QUERY_MSG = "NCR-QUERY".encode("utf8")

clients = []

async def init():
    spi = busio.SPI(board.SCK, MOSI=board.MOSI, MISO=board.MISO)
    radio_cs = digitalio.DigitalInOut(board.D7)
    radio_reset = digitalio.DigitalInOut(board.D25)
    global radio
    radio = adafruit_rfm9x.RFM9x(spi, radio_cs, radio_reset, 433.0)
    radio.enable_crc = True
    print("Radio initialized!")

    server = await asyncio.start_server(on_connect, '0.0.0.0', PORT)
    print("Server started at :{}!".format(PORT))

    # Kickoff radio polling
    while True:
        await asyncio.create_task(poll_cmd())

async def on_connect(reader, writer):
    address = writer.get_extra_info('peername')
    print("Client connected: {}".format(address))

    # Send hello to clients
    writer.write("NC🚀2020-C&C {}".format(VERSION).encode("utf8"))
    clients.append({
        "address": address,
        "reader": reader,
        "writer": writer
    })

async def poll_cmd():
    # Await data on channel 42
    data = radio.receive(timeout=0.05, rx_filter=42)

    if data is None:
        return

    for client in clients:
        # Check if client has closed connection
        if client["writer"].is_closing():
            # TODO: Remove client from array
            #clients.remove(client)
            print("Client disconnected: {}".format(client["address"]))
            continue

        # Process radio command
        if data is QUERY_MSG:
            pass # TODO: Add query command to each client
        elif data is TRIGGER_MSG:
            await send_trigger(client)
        else:
            print("Misc data received: {}".format(data))

async def send_trigger(client):
    writer = client["writer"]
    writer.write("GODSPEED")
    await writer.drain()

async def request_status(client):
    reader = client["reader"]
    writer = client["writer"]
    address = client["address"]

if __name__ == "__main__":
    asyncio.run(init(), debug=True)
