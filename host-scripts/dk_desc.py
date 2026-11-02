import sys, ctypes
sys.path.insert(0, r'<RM9_WORKDIR>\refs')
import rm9link as R
d = ctypes.WinDLL(r'C:\Program Files\UsbDk Runtime Library\UsbDkHelper.dll', use_last_error=True)
p = ctypes.POINTER(R._DkInfo)()
n = ctypes.c_ulong(0)
print('list', d.UsbDk_GetDevicesList(ctypes.byref(p), ctypes.byref(n)), n.value)
for i in range(n.value):
    x = p[i]
    desc = bytes(x.Desc)
    print(i, 'vid:pid %02x%02x:%02x%02x' % (desc[9], desc[8], desc[11], desc[10]), 'port', x.Port, 'speed', x.Speed, 'bcdUSB %02x%02x' % (desc[3], desc[2]), 'cfgs', desc[17], x.ID.DeviceID[:40], x.ID.InstanceID[:40])
    if desc[9] == 0x12 and desc[8] == 0x09:
        req = R._DkReq if False else None
        class _CfgReq(ctypes.Structure):
            _fields_ = [('Index', ctypes.c_uint64)]
        buf = ctypes.c_void_p()
        ln = ctypes.c_ulong(0)
        d.UsbDk_GetConfigurationDescriptor.argtypes = [ctypes.POINTER(R._DkId), ctypes.c_ubyte, ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(ctypes.c_ulong)] if False else None
        try:
            r = d.UsbDk_GetConfigurationDescriptor(ctypes.byref(x.ID), ctypes.c_uint8(0), ctypes.byref(buf), ctypes.byref(ln))
            print('  cfgdesc ok', r, 'len', ln.value)
            if r and buf.value:
                print('  ', bytes((ctypes.c_ubyte * min(ln.value, 256)).from_address(buf.value)).hex())
        except Exception as e:
            print('  cfgdesc exc', e)
d.UsbDk_ReleaseDevicesList(p)
