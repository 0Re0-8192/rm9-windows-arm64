# -*- coding: utf-8 -*-
"""EDL (9008) minimal recovery: Sahara -> upload firehose.elf -> configure(ufs) -> READ-ONLY look at
LUN0/LUN4 GPT -> <power value="reset"/>.  NO program/erase commands."""
import struct
import sys
import time
from pathlib import Path

import serial
import serial.tools.list_ports

LOADER = r"<RM9_WORKDIR>\toolbox\rm9-toolbox\res\firehose.elf"
SECTOR = 4096
loader = open(LOADER, "rb").read()


def log(s):
    print(s, flush=True)


PORT = None
t0 = time.time()
while time.time() - t0 < 120 and PORT is None:
    for prt in serial.tools.list_ports.comports():
        if prt.vid == 0x05C6 and prt.pid == 0x9008:
            PORT = prt.device
    time.sleep(1)
if PORT is None:
    sys.exit("no 9008 port")
log("port " + PORT)
p = serial.Serial(PORT, 115200, timeout=2)
p.reset_input_buffer()
wr = p.write


def rd_exact(n, timeout=5):
    p.timeout = timeout
    buf = b""
    while len(buf) < n:
        c = p.read(n - len(buf))
        if not c:
            break
        buf += c
    return buf


def read_pkt(timeout=5):
    hdr = rd_exact(8, timeout)
    if len(hdr) < 8:
        return None
    cmd, ln = struct.unpack("<II", hdr[:8])
    payload = rd_exact(ln - 8, timeout) if ln > 8 else b""
    return (cmd, ln, payload)


def hello_resp(pl):
    vv = min(struct.unpack("<I", pl[:4])[0] if len(pl) >= 4 else 2, 2)
    wr(struct.pack("<IIIIIIIIIIII", 0x02, 0x30, vv, 1, 0, 0, 0, 0, 0, 0, 0, 0))


def drain(sec):
    p.timeout = 0.3
    acc = b""
    t = time.time()
    while time.time() - t < sec:
        c = p.read(65536)
        if c:
            acc += c
    return acc


def fh_read(lun, start, count, timeout=60):
    wr(('<?xml version="1.0" ?><data><read physical_partition_number="%d" SECTOR_SIZE_IN_BYTES="4096" '
        'start_sector="%d" num_partition_sectors="%d"/></data>' % (lun, start, count)).encode())
    need = count * SECTOR
    acc, buf, ack = b"", b"", False
    t = time.time()
    while time.time() - t < timeout:
        p.timeout = 1
        c = p.read(65536)
        if c:
            if not ack:
                acc += c
                ai = acc.find(b'value="ACK"')
                if ai != -1:
                    di = acc.find(b"</data>", ai)
                    if di != -1:
                        buf += acc[di + 7:]
                        ack = True
            else:
                buf += c
        if ack and len(buf) >= need:
            return buf[:need]
    return None


log("=== Sahara ===")
hello = None
for _ in range(8):
    res = read_pkt(3)
    if res and res[0] == 0x01:
        hello = res
        break
    wr(struct.pack("<II", 0x05, 0x8))
    time.sleep(0.2)
    wr(struct.pack("<II", 0x07, 0x8))
    time.sleep(0.4)
if hello is None:
    sys.exit("no hello")
hello_resp(hello[2])
done, loops = False, 0
while loops < 9000 and not done:
    loops += 1
    res = read_pkt(5)
    if res is None:
        continue
    cmd, ln, payload = res
    if cmd in (0x03, 0x12):
        if cmd == 0x12 and len(payload) >= 24:
            image_id, offset, dlen = struct.unpack("<QQQ", payload[:24])
        elif cmd == 0x03 and len(payload) >= 12:
            image_id, offset, dlen = struct.unpack("<III", payload[:12])
        else:
            continue
        chunk = loader[offset:offset + dlen]
        if len(chunk) < dlen:
            chunk += b"\xFF" * (dlen - len(chunk))
        wr(chunk)
    elif cmd == 0x01:
        hello_resp(payload)
    elif cmd == 0x04:
        img, st = struct.unpack("<II", payload[:8]) if len(payload) >= 8 else (-1, -1)
        if st == 0:
            wr(struct.pack("<II", 0x05, 0x8))
            r2 = read_pkt(4)
            if r2 and r2[0] == 0x06:
                done = True
    elif cmd == 0x06:
        done = True

acc = drain(2.0)
t = time.time()
while b"<?xml" not in acc and time.time() - t < 30:
    acc += drain(1.0)
log("firehose up")
wr(b'<?xml version="1.0" ?><data><configure MemoryName="ufs" Verbose="0" AlwaysValidate="0" '
   b'MaxDigestTableSizeInBytes="2048" MaxPayloadSizeToTargetInBytes="1048576" ZLPAwareHost="1" '
   b'SkipStorageInit="0" SkipWrite="1"/></data>')
resp = drain(3.0)
log("configure: " + ("ACK" if b"ACK" in resp else "NO-ACK " + resp[:200].decode("latin1")))

for lun in (0, 4):
    g = fh_read(lun, 0, 34)
    if g and g.find(b"EFI PART") != -1:
        off = g.find(b"EFI PART")
        entries_lba = struct.unpack("<Q", g[off + 72:off + 80])[0]
        num = struct.unpack("<I", g[off + 80:off + 84])[0]
        names = []
        base = (off - SECTOR) + entries_lba * SECTOR
        for i in range(min(num, 128)):
            e = base + i * 128
            if len(g) < e + 128:
                break
            if g[e:e + 16] != b"\0" * 16:
                names.append(g[e + 56:e + 128].decode("utf-16-le", "ignore").split("\0")[0])
        log("LUN%d GPT ok: %d partitions: %s" % (lun, len(names), ",".join(names[:20])))
    else:
        log("LUN%d GPT read FAILED" % lun)

log("=== power reset ===")
wr(b'<?xml version="1.0" ?><data><power value="reset" DelayInSeconds="2"/></data>')
time.sleep(3)
log("reset sent: " + drain(2.0)[:200].decode("latin1", "replace"))
p.close()
