# PC side of the USB function experiment, WinUSB through ctypes (the device has the WINUSB compatible ID, so Windows registers the default interface GUID {DEE824EF-729B-4A0E-9C14-B7117D33A817}; libusb cannot open it).
# Waits for the phone's Windows (VID 1209 PID 0001), then writes a message to bulk OUT 0x01 every second and tries to read bulk IN 0x81; log to a file.
#   python pc_usbpump.py [seconds] [logfile]
import ctypes, sys, time, uuid
from ctypes import wintypes as W

secs = int(sys.argv[1]) if len(sys.argv) > 1 else 900
log = sys.argv[2] if len(sys.argv) > 2 else r'<RM9_WORKDIR>\winboot\pc_usbpump.log'


def L(m):
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


class SP_DEVICE_INTERFACE_DATA(ctypes.Structure):
    _fields_ = [('cbSize', W.DWORD), ('InterfaceClassGuid', GUID), ('Flags', W.DWORD), ('Reserved', ctypes.c_void_p)]


setupapi = ctypes.WinDLL('setupapi', use_last_error=True)
kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
winusb = ctypes.WinDLL('winusb', use_last_error=True)
setupapi.SetupDiGetClassDevsW.restype = ctypes.c_void_p
setupapi.SetupDiGetClassDevsW.argtypes = [ctypes.POINTER(GUID), W.LPCWSTR, W.HWND, W.DWORD]
setupapi.SetupDiEnumDeviceInterfaces.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(GUID), W.DWORD, ctypes.POINTER(SP_DEVICE_INTERFACE_DATA)]
setupapi.SetupDiGetDeviceInterfaceDetailW.argtypes = [ctypes.c_void_p, ctypes.POINTER(SP_DEVICE_INTERFACE_DATA), ctypes.c_void_p, W.DWORD, ctypes.POINTER(W.DWORD), ctypes.c_void_p]
kernel32.CreateFileW.restype = ctypes.c_void_p
kernel32.CreateFileW.argtypes = [W.LPCWSTR, W.DWORD, W.DWORD, ctypes.c_void_p, W.DWORD, W.DWORD, ctypes.c_void_p]
winusb.WinUsb_Initialize.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
winusb.WinUsb_WritePipe.argtypes = [ctypes.c_void_p, ctypes.c_ubyte, ctypes.c_char_p, W.ULONG, ctypes.POINTER(W.ULONG), ctypes.c_void_p]
winusb.WinUsb_ReadPipe.argtypes = [ctypes.c_void_p, ctypes.c_ubyte, ctypes.c_char_p, W.ULONG, ctypes.POINTER(W.ULONG), ctypes.c_void_p]
winusb.WinUsb_SetPipePolicy.argtypes = [ctypes.c_void_p, ctypes.c_ubyte, W.ULONG, W.ULONG, ctypes.c_void_p]

GUID_WINUSB = guid('{DEE824EF-729B-4A0E-9C14-B7117D33A817}')


def find_path():
    hdev = setupapi.SetupDiGetClassDevsW(ctypes.byref(GUID_WINUSB), None, None, 0x12)   # PRESENT | DEVICEINTERFACE
    i = 0
    found = []
    while True:
        d = SP_DEVICE_INTERFACE_DATA()
        d.cbSize = ctypes.sizeof(d)
        if not setupapi.SetupDiEnumDeviceInterfaces(hdev, None, ctypes.byref(GUID_WINUSB), i, ctypes.byref(d)):
            break
        i += 1
        need = W.DWORD(0)
        setupapi.SetupDiGetDeviceInterfaceDetailW(hdev, ctypes.byref(d), None, 0, ctypes.byref(need), None)
        buf = ctypes.create_string_buffer(need.value)
        ctypes.cast(buf, ctypes.POINTER(W.DWORD))[0] = 8 if ctypes.sizeof(ctypes.c_void_p) == 8 else 6
        if setupapi.SetupDiGetDeviceInterfaceDetailW(hdev, ctypes.byref(d), buf, need.value, None, None):
            path = ctypes.wstring_at(ctypes.addressof(buf) + 4)
            found.append(path)
    return [p for p in found if 'vid_1209&pid_0001' in p.lower()], found


L('--- start (winusb)')
end = time.time() + secs
hdl = None
iface = ctypes.c_void_p()
n = 0
lastnote = 0
while time.time() < end:
    if hdl is None:
        mine, allp = find_path()
        if not mine:
            if time.time() - lastnote > 30:
                L('device not there yet (winusb interfaces: %d)' % len(allp))
                lastnote = time.time()
            time.sleep(1)
            continue
        L('path: %s' % mine[0])
        hdl = kernel32.CreateFileW(mine[0], 0xC0000000, 3, None, 3, 0x40000080, None)   # RW, share RW, OPEN_EXISTING, OVERLAPPED|NORMAL
        if hdl in (None, ctypes.c_void_p(-1).value):
            L('CreateFile failed %d' % ctypes.get_last_error())
            hdl = None
            time.sleep(2)
            continue
        if not winusb.WinUsb_Initialize(hdl, ctypes.byref(iface)):
            L('WinUsb_Initialize failed %d' % ctypes.get_last_error())
            kernel32.CloseHandle(ctypes.c_void_p(hdl))
            hdl = None
            time.sleep(2)
            continue
        L('WinUSB open ok')
        t = W.ULONG(1000)
        for ep in (0x01, 0x81):
            winusb.WinUsb_SetPipePolicy(iface, ep, 3, 4, ctypes.byref(t))   # PIPE_TRANSFER_TIMEOUT
    msg = ('PC->phone hello #%d' % n).encode()
    done = W.ULONG(0)
    ok = winusb.WinUsb_WritePipe(iface, 0x01, msg, len(msg), ctypes.byref(done), None)
    L('write ok=%s wrote=%d err=%d' % (bool(ok), done.value, 0 if ok else ctypes.get_last_error()))
    rb = ctypes.create_string_buffer(512)
    got = W.ULONG(0)
    ok = winusb.WinUsb_ReadPipe(iface, 0x81, rb, 512, ctypes.byref(got), None)
    L('read ok=%s bytes=%d err=%d : %r' % (bool(ok), got.value, 0 if ok else ctypes.get_last_error(), rb.raw[:got.value][:64]))
    n += 1
    time.sleep(0.5)
L('--- end')
