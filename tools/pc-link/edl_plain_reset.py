"""Plain Sahara RESET of a phone sitting in EDL (9008).  No flash / no storage access.
Handshake: read HELLO (cmd 1) -> answer HELLO_RESP (cmd 2, mode 0) -> send RESET (cmd 7)."""
import struct
import sys
import time

import serial
import serial.tools.list_ports


def find():
    for p in serial.tools.list_ports.comports():
        if p.vid == 0x05C6 and p.pid == 0x9008:
            return p.device
    return None


dev = find()
print("port:", dev)
if not dev:
    sys.exit("no 9008 port")
s = serial.Serial(dev, 115200, timeout=2, write_timeout=3)
hdr = s.read(8)
print("rx:", hdr.hex())
if len(hdr) == 8 and struct.unpack("<I", hdr[:4])[0] == 1:
    ln = struct.unpack("<I", hdr[4:])[0]
    s.read(ln - 8)
    s.write(struct.pack("<IIIIIIIIIIII", 2, 48, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0))   # HELLO_RESP, mode 0
    s.flush()
    time.sleep(0.5)
    r = s.read(64)
    print("after hello_resp:", r[:16].hex())
s.write(struct.pack("<II", 7, 8))      # RESET
s.flush()
time.sleep(1)
print("reset sent; reply:", s.read(16).hex())
s.close()
