# Dump what the PC's USB stack sees for a device, via the hub IOCTLs (works without any driver bound):
# speed, device descriptor, full configuration descriptor, BOS.  Polls until a device with the given VID:PID appears.
#   python pc_usbdesc.py [vid=1209] [seconds=1200] [logfile]      (vid 'all' dumps every device once)
import ctypes, struct, sys, time, uuid
from ctypes import wintypes as W

vid = sys.argv[1] if len(sys.argv) > 1 else '1209'
secs = int(sys.argv[2]) if len(sys.argv) > 2 else 1200
log = sys.argv[3] if len(sys.argv) > 3 else r'<RM9_WORKDIR>\winboot\pc_usbdesc.log'


def L(m):
    print(m)
    with open(log, 'a', encoding='utf-8') as f:
        f.write('%s %s\n' % (time.strftime('%H:%M:%S'), m))


class GUID(ctypes.Structure):
    _fields_ = [('Data1', ctypes.c_ulong), ('Data2', ctypes.c_ushort), ('Data3', ctypes.c_ushort), ('Data4', ctypes.c_ubyte * 8)]


def guid(s):
    u = uuid.UUID(s)
    g = GUID()
    g.Data1, g.Data2, g.Data3 = u.time_low, u.time_mid, u.time_hi_version
    for i, b in enumerate(u.bytes[8:]):
        g.Data4[i] = b
    return g


class SPID(ctypes.Structure):
    _fields_ = [('cbSize', W.DWORD), ('Guid', GUID), ('Flags', W.DWORD), ('Reserved', ctypes.c_void_p)]


sa = ctypes.WinDLL('setupapi', use_last_error=True)
k = ctypes.WinDLL('kernel32', use_last_error=True)
sa.SetupDiGetClassDevsW.restype = ctypes.c_void_p
sa.SetupDiGetClassDevsW.argtypes = [ctypes.POINTER(GUID), W.LPCWSTR, W.HWND, W.DWORD]
sa.SetupDiEnumDeviceInterfaces.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(GUID), W.DWORD, ctypes.POINTER(SPID)]
sa.SetupDiGetDeviceInterfaceDetailW.argtypes = [ctypes.c_void_p, ctypes.POINTER(SPID), ctypes.c_void_p, W.DWORD, ctypes.POINTER(W.DWORD), ctypes.c_void_p]
k.CreateFileW.restype = ctypes.c_void_p
k.CreateFileW.argtypes = [W.LPCWSTR, W.DWORD, W.DWORD, ctypes.c_void_p, W.DWORD, W.DWORD, ctypes.c_void_p]
k.DeviceIoControl.argtypes = [ctypes.c_void_p, W.DWORD, ctypes.c_void_p, W.DWORD, ctypes.c_void_p, W.DWORD, ctypes.POINTER(W.DWORD), ctypes.c_void_p]
HUBG = guid('{F18A0E88-C30C-11D0-8815-00A0C906BED8}')


def hubs():
    h = sa.SetupDiGetClassDevsW(ctypes.byref(HUBG), None, None, 0x12)
    out = []
    i = 0
    while True:
        d = SPID(); d.cbSize = ctypes.sizeof(d)
        if not sa.SetupDiEnumDeviceInterfaces(h, None, ctypes.byref(HUBG), i, ctypes.byref(d)):
            break
        i += 1
        need = W.DWORD(0)
        sa.SetupDiGetDeviceInterfaceDetailW(h, ctypes.byref(d), None, 0, ctypes.byref(need), None)
        buf = ctypes.create_string_buffer(need.value)
        ctypes.cast(buf, ctypes.POINTER(W.DWORD))[0] = 8
        if sa.SetupDiGetDeviceInterfaceDetailW(h, ctypes.byref(d), buf, need.value, None, None):
            out.append(ctypes.wstring_at(ctypes.addressof(buf) + 4))
    return out


def ioctl(h, code, inb, outlen):
    ib = ctypes.create_string_buffer(inb, len(inb))
    ob = ctypes.create_string_buffer(outlen)
    ret = W.DWORD(0)
    ok = k.DeviceIoControl(h, code, ib, len(inb), ob, outlen, ctypes.byref(ret), None)
    return ok, ob.raw[:ret.value]


def getdesc(h, port, typ, idx, length):
    req = struct.pack('<I', port) + struct.pack('<BBHHH', 0x80, 6, (typ << 8) | idx, 0, length)
    ok, data = ioctl(h, 0x220410, req, 12 + length)
    return data[12:] if ok else None


def hexs(b):
    return ' '.join('%02X' % x for x in b)


seen = set()
end = time.time() + secs
L('--- start (vid=%s)' % vid)
while time.time() < end:
    for hp in hubs():
        h = k.CreateFileW(hp, 0xC0000000, 3, None, 3, 0, None)
        if h in (None, ctypes.c_void_p(-1).value):
            continue
        for port in range(1, 16):
            ok, d = ioctl(h, 0x220448, struct.pack('<I', port), 512)
            if not ok or len(d) < 35:
                continue
            desc = d[4:22]
            vi, pi = struct.unpack_from('<HH', desc, 8)
            conn = struct.unpack_from('<I', d, 31)[0]
            if conn != 1:
                continue
            key = (hp, port, vi, pi)
            if vid != 'all' and '%04x' % vi != vid.lower():
                continue
            if key in seen:
                continue
            seen.add(key)
            L('hub %s port %d  VID %04X PID %04X speed=%d cfgval=%d addr=%d' % (hp[-40:], port, vi, pi, d[23], d[22], struct.unpack_from('<H', d, 25)[0]))
            L('  device desc: ' + hexs(desc))
            cd = getdesc(h, port, 2, 0, 9)
            if cd:
                tl = struct.unpack_from('<H', cd, 2)[0]
                cd = getdesc(h, port, 2, 0, tl)
                L('  config desc (%d): %s' % (tl, hexs(cd) if cd else None))
            bos = getdesc(h, port, 0x0F, 0, 5)
            if bos and len(bos) >= 5:
                tl = struct.unpack_from('<H', bos, 2)[0]
                bos = getdesc(h, port, 0x0F, 0, tl)
            L('  BOS: ' + (hexs(bos) if bos else 'none'))
            ms = getdesc(h, port, 3, 0xEE, 18)
            L('  string 0xEE: ' + (hexs(ms) if ms else 'none'))
        k.CloseHandle(ctypes.c_void_p(h))
    if vid == 'all':
        break
    time.sleep(0.5)
L('--- end')
