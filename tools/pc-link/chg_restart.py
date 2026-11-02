"""chg_restart.py [--probe] [--vid 19d2] [--pid ffcc]
Sends the RM9 'remote restart' command to the phone's USB mass-storage gadget (19D2:FFCC = the off-mode charging
composition) as a raw USB Bulk-Only-Transport command through UsbDk (Windows has no storage driver bound to it):
  CBW 'USBC', CDB = F0 'R' 'M' '9' '!' 00   ->   patched kernel (f_mass_storage.c) calls kernel_restart(NULL).
--probe sends opcode F1 instead (harmless: the gadget answers CHECK CONDITION / invalid command), to prove the path.
Patch source: nx769j-steam-kernel/analysis/rm9-patch-fsg-restart.sh.  UsbDk must be installed (rm9link uses it too)."""
import ctypes
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rm9link as L          # noqa: E402  (reuse its UsbDk structures)

from ctypes import wintypes as W  # noqa: E402


class _CfgReq(ctypes.Structure):
    _fields_ = [("ID", L._DkId), ("Index", ctypes.c_uint64)]


def arg(name, default):
    return sys.argv[sys.argv.index(name) + 1].lower() if name in sys.argv else default


def main():
    probe = "--probe" in sys.argv
    vid, pid = int(arg("--vid", "19d2"), 16), int(arg("--pid", "ffcc"), 16)
    rt = r"C:\Program Files\UsbDk Runtime Library"
    d = ctypes.WinDLL(os.path.join(rt, "UsbDkHelper.dll"), use_last_error=True)
    p = ctypes.POINTER(L._DkInfo)()
    n = ctypes.c_ulong(0)
    if not d.UsbDk_GetDevicesList(ctypes.byref(p), ctypes.byref(n)):
        sys.exit("UsbDk_GetDevicesList failed")
    target = None
    for i in range(n.value):
        dv = bytes(p[i].Desc)
        if struct.unpack_from("<HH", dv, 8) == (vid, pid):
            target = L._DkId()
            ctypes.memmove(ctypes.byref(target), ctypes.byref(p[i].ID), ctypes.sizeof(L._DkId))
    d.UsbDk_ReleaseDevicesList(p)
    if target is None:
        sys.exit("device %04x:%04x not found" % (vid, pid))
    # endpoints from the configuration descriptor
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
    ep_in = ep_out = None
    i = 0
    while i + 2 <= len(cfg) and cfg[i]:
        ln, ty = cfg[i], cfg[i + 1]
        if ty == 5 and cfg[i + 3] & 3 == 2:                 # bulk endpoint
            if cfg[i + 2] & 0x80:
                ep_in = cfg[i + 2]
            else:
                ep_out = cfg[i + 2]
        i += ln
    print("config descriptor %d bytes, bulk IN=%s OUT=%s" % (len(cfg), hex(ep_in or 0), hex(ep_out or 0)))
    if not (ep_in and ep_out):
        sys.exit("no bulk endpoints found")

    t = L.UsbdkTransport.__new__(L.UsbdkTransport)         # reuse its transfer helpers without its VID-0x1209 lookup
    t.d = d
    t.k = ctypes.WinDLL("kernel32", use_last_error=True)
    k = t.k
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
    t.red = d.UsbDk_StartRedirect(ctypes.byref(target))
    if not t.red:
        sys.exit("UsbDk_StartRedirect failed %d" % ctypes.get_last_error())
    t.sys = d.UsbDk_GetRedirectorSystemHandle(t.red)
    t.evr = k.CreateEventW(None, True, False, None)
    t.evw = k.CreateEventW(None, True, False, None)
    t.rbuf = ctypes.create_string_buffer(65536)

    op = 0xF1 if probe else 0xF0
    cdb = bytes([op, ord("R"), ord("M"), ord("9"), ord("!"), 0]).ljust(16, b"\0")
    cbw = struct.pack("<4sIIBBB", b"USBC", 0x524D3921, 0, 0, 0, 6) + cdb
    assert len(cbw) == 31
    buf = ctypes.create_string_buffer(cbw, len(cbw))
    r = t._xfer(True, ep_out, buf, len(cbw), 3000)
    print("CBW (op %02x) sent: %s" % (op, r))
    try:
        got = t._xfer(False, ep_in, t.rbuf, 64, 3000)
        if got is None:
            print("no CSW within 3 s")
        else:
            csw = t.rbuf.raw[:got]
            print("CSW %d bytes: %s" % (got, csw.hex()))
            if got == 13:
                print("  signature=%s tag=%08x residue=%d status=%d (0 ok, 1 command failed)" % (csw[:4], *struct.unpack_from("<II", csw, 4), csw[12]))
    except Exception as e:
        print("CSW read error:", e)
    d.UsbDk_StopRedirect(t.red)


main()
