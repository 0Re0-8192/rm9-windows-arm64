# -*- coding: utf-8 -*-
"""edl_usbdk.py probe|sreset|fhreset [--vid 19d2] [--pid 0112]
EDL (Sahara/Firehose) over raw bulk USB through UsbDk, for a PC that has no Qualcomm serial driver bound (the phone shows up as
"QUSB_BULK_CID:0448_SN:..." with an error status).  Same protocol as edl_plain_reset.py / edl_firehose_reset.py; NO program/erase commands.
  probe    read the Sahara HELLO packet and print it (answers nothing)
  sreset   HELLO -> HELLO_RESP(mode 0) -> Sahara RESET (cmd 7)
  fhreset  HELLO -> upload firehose.elf -> <configure SkipWrite=1> -> <power value="reset"/>
Needs UsbDk and rm9link.py next to this file (its UsbDk structures are reused)."""
import ctypes
import os
import struct
import sys
import time
from ctypes import wintypes as W

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rm9link as L  # noqa: E402

LOADER = os.environ.get("EDL_LOADER", r"C:\rm9work\firehose.elf")


def arg(name, default):
    return sys.argv[sys.argv.index(name) + 1].lower() if name in sys.argv else default


def log(s):
    print(time.strftime("%H:%M:%S ") + s, flush=True)


class _CfgReq(ctypes.Structure):
    _fields_ = [("ID", L._DkId), ("Index", ctypes.c_uint64)]


class Bulk:
    """pyserial-like write()/read() over the first bulk IN/OUT endpoint pair of the device."""

    def __init__(self, vid, pid):
        rt = r"C:\Program Files\UsbDk Runtime Library"
        d = self.d = ctypes.WinDLL(os.path.join(rt, "UsbDkHelper.dll"), use_last_error=True)
        k = self.k = ctypes.WinDLL("kernel32", use_last_error=True)
        d.UsbDk_StartRedirect.restype = ctypes.c_void_p
        d.UsbDk_StartRedirect.argtypes = [ctypes.POINTER(L._DkId)]
        d.UsbDk_GetRedirectorSystemHandle.restype = ctypes.c_void_p
        d.UsbDk_GetRedirectorSystemHandle.argtypes = [ctypes.c_void_p]
        d.UsbDk_ReadPipe.argtypes = [ctypes.c_void_p, ctypes.POINTER(L._DkReq), ctypes.POINTER(L._Ov)]
        d.UsbDk_WritePipe.argtypes = [ctypes.c_void_p, ctypes.POINTER(L._DkReq), ctypes.POINTER(L._Ov)]
        d.UsbDk_AbortPipe.argtypes = [ctypes.c_void_p, ctypes.c_uint64]
        d.UsbDk_StopRedirect.argtypes = [ctypes.c_void_p]
        k.CreateEventW.restype = ctypes.c_void_p
        k.CreateEventW.argtypes = [ctypes.c_void_p, W.BOOL, W.BOOL, W.LPCWSTR]
        k.WaitForSingleObject.argtypes = [ctypes.c_void_p, W.DWORD]
        k.ResetEvent.argtypes = [ctypes.c_void_p]
        p = ctypes.POINTER(L._DkInfo)()
        n = ctypes.c_ulong(0)
        if not d.UsbDk_GetDevicesList(ctypes.byref(p), ctypes.byref(n)):
            sys.exit("UsbDk_GetDevicesList failed")
        target = None
        for i in range(n.value):
            if struct.unpack_from("<HH", bytes(p[i].Desc), 8) == (vid, pid):
                target = L._DkId()
                ctypes.memmove(ctypes.byref(target), ctypes.byref(p[i].ID), ctypes.sizeof(L._DkId))
        d.UsbDk_ReleaseDevicesList(p)
        if target is None:
            sys.exit("device %04x:%04x not found" % (vid, pid))
        d.UsbDk_GetConfigurationDescriptor.argtypes = [ctypes.POINTER(_CfgReq), ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(ctypes.c_ulong)]
        req = _CfgReq()
        ctypes.memmove(ctypes.byref(req.ID), ctypes.byref(target), ctypes.sizeof(L._DkId))
        req.Index = 0
        dp = ctypes.c_void_p()
        dl = ctypes.c_ulong(0)
        if not d.UsbDk_GetConfigurationDescriptor(ctypes.byref(req), ctypes.byref(dp), ctypes.byref(dl)):
            sys.exit("UsbDk_GetConfigurationDescriptor failed")
        cfg = ctypes.string_at(dp.value, dl.value)
        d.UsbDk_ReleaseConfigurationDescriptor.argtypes = [ctypes.c_void_p]
        d.UsbDk_ReleaseConfigurationDescriptor(dp)
        self.ep_in = self.ep_out = None
        i = 0
        while i + 2 <= len(cfg) and cfg[i]:
            ln, ty = cfg[i], cfg[i + 1]
            if ty == 5 and cfg[i + 3] & 3 == 2:
                if cfg[i + 2] & 0x80 and self.ep_in is None:
                    self.ep_in = cfg[i + 2]
                elif not cfg[i + 2] & 0x80 and self.ep_out is None:
                    self.ep_out = cfg[i + 2]
            i += ln
        log("config descriptor %d bytes, bulk in=%s out=%s" % (len(cfg), self.ep_in and hex(self.ep_in), self.ep_out and hex(self.ep_out)))
        if self.ep_in is None or self.ep_out is None:
            sys.exit("no bulk endpoint pair")
        self.red = d.UsbDk_StartRedirect(ctypes.byref(target))
        if not self.red:
            sys.exit("UsbDk_StartRedirect failed %d" % ctypes.get_last_error())
        self.sys = d.UsbDk_GetRedirectorSystemHandle(self.red)
        self.evr = k.CreateEventW(None, True, False, None)
        self.evw = k.CreateEventW(None, True, False, None)
        self.rbuf = ctypes.create_string_buffer(1 << 20)
        self.acc = b""

    def _xfer(self, write, ep, buf, length, timeout_ms):
        req = L._DkReq()
        req.EndpointAddress = ep
        req.Buffer = ctypes.cast(buf, ctypes.c_void_p).value
        req.BufferLength = length
        req.TransferType = 1
        ov = L._Ov()
        ev = self.evw if write else self.evr
        ov.hEvent = ev
        self.k.ResetEvent(ev)
        fn = self.d.UsbDk_WritePipe if write else self.d.UsbDk_ReadPipe
        r = fn(self.red, ctypes.byref(req), ctypes.byref(ov))
        if r == 0:
            raise RuntimeError("submit failed ep=0x%02x" % ep)
        if r == 2:
            if self.k.WaitForSingleObject(ev, timeout_ms) != 0:
                self.d.UsbDk_AbortPipe(self.red, ep)
                self.k.WaitForSingleObject(ev, 5000)
                return None
        if req.Result.UsbdStatus != 0:
            raise RuntimeError("usbd status 0x%x ep=0x%02x" % (req.Result.UsbdStatus, ep))
        return req.Result.BytesTransferred

    def write(self, data):
        off = 0
        while off < len(data):
            chunk = data[off:off + (1 << 20)]
            buf = ctypes.create_string_buffer(bytes(chunk), len(chunk))
            if self._xfer(True, self.ep_out, buf, len(chunk), 10000) is None:
                raise RuntimeError("bulk OUT timeout")
            off += len(chunk)

    def read_some(self, timeout_s):
        n = self._xfer(False, self.ep_in, self.rbuf, 65536, int(timeout_s * 1000))
        return b"" if not n else self.rbuf.raw[:n]

    def read(self, n, timeout_s):
        t = time.time()
        while len(self.acc) < n and time.time() - t < timeout_s:
            self.acc += self.read_some(min(1.0, max(0.1, timeout_s - (time.time() - t))))
        out, self.acc = self.acc[:n], self.acc[n:]
        return out

    def drain(self, sec):
        t = time.time()
        got = self.acc
        self.acc = b""
        while time.time() - t < sec:
            got += self.read_some(0.3)
        return got

    def close(self):
        self.d.UsbDk_StopRedirect(self.red)


def read_pkt(b, timeout=5):
    hdr = b.read(8, timeout)
    if len(hdr) < 8:
        return None
    cmd, ln = struct.unpack("<II", hdr)
    pl = b.read(ln - 8, timeout) if ln > 8 else b""
    return cmd, ln, pl


def hello_resp(b, pl):
    vv = min(struct.unpack("<I", pl[:4])[0] if len(pl) >= 4 else 2, 2)
    b.write(struct.pack("<IIIIIIIIIIII", 0x02, 0x30, vv, 1, 0, 0, 0, 0, 0, 0, 0, 0))


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "probe"
    vid, pid = int(arg("--vid", "19d2"), 16), int(arg("--pid", "0112"), 16)
    b = Bulk(vid, pid)
    try:
        res = read_pkt(b, 4)
        if res is None:
            log("no packet within 4 s (HELLO not pending)")
            if mode == "probe":
                return
        else:
            log("rx cmd=0x%x len=%d payload=%s" % (res[0], res[1], res[2].hex()))
        if mode == "probe":
            return
        if res is None or res[0] != 1:
            log("no HELLO; aborting (nothing sent)")
            return
        hello_resp(b, res[2])
        if mode == "sreset":
            time.sleep(0.5)
            r = read_pkt(b, 3)
            log("after HELLO_RESP: " + (repr(r[:2]) + r[2][:24].hex() if r else "nothing"))
            b.write(struct.pack("<II", 7, 8))
            time.sleep(1)
            log("RESET sent; reply: " + b.drain(1.0).hex())
            return
        if mode == "fhreset":
            loader = open(LOADER, "rb").read()
            log("loader %d bytes" % len(loader))
            done, loops = False, 0
            while loops < 9000 and not done:
                loops += 1
                res = read_pkt(b, 5)
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
                    b.write(chunk)
                elif cmd == 0x01:
                    hello_resp(b, payload)
                elif cmd == 0x04:
                    img, st = struct.unpack("<II", payload[:8]) if len(payload) >= 8 else (-1, -1)
                    log("end of image transfer id=%d status=%d" % (img, st))
                    if st == 0:
                        b.write(struct.pack("<II", 0x05, 0x8))
                        r2 = read_pkt(b, 4)
                        if r2 and r2[0] == 0x06:
                            done = True
                elif cmd == 0x06:
                    done = True
            log("sahara done=%s loops=%d" % (done, loops))
            acc = b.drain(2.0)
            t = time.time()
            while b"<?xml" not in acc and time.time() - t < 30:
                acc += b.drain(1.0)
            log("firehose up: " + acc[:120].decode("latin1", "replace").replace("\n", " "))
            b.write(b'<?xml version="1.0" ?><data><configure MemoryName="ufs" Verbose="0" AlwaysValidate="0" '
                    b'MaxDigestTableSizeInBytes="2048" MaxPayloadSizeToTargetInBytes="1048576" ZLPAwareHost="1" '
                    b'SkipStorageInit="0" SkipWrite="1"/></data>')
            resp = b.drain(3.0)
            log("configure: " + ("ACK" if b"ACK" in resp else "NO-ACK " + resp[:200].decode("latin1", "replace")))
            b.write(b'<?xml version="1.0" ?><data><power value="reset" DelayInSeconds="2"/></data>')
            time.sleep(3)
            log("reset sent: " + b.drain(2.0)[:200].decode("latin1", "replace"))
    finally:
        try:
            b.close()
        except Exception:
            pass


if __name__ == "__main__":
    main()
