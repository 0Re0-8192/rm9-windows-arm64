#!/usr/bin/env python
# PC side of the RM9 USB remote-control link (agent: refs/winpe/usbfn_agent.ps1 on the phone's Windows).
#   python rm9link.py ping | ver | exec [-t SEC] <cmd...> | put <local> <remote> | get <remote> <local> | reboot | wait
#   global option:  --tcp PORT   talk to a local agent test instance instead of USB (127.0.0.1:PORT)
# Python API:  with Link() as L: L.exec('ver'); L.put(local, remote); L.get(remote, local)
# Transport: WinUSB via ctypes (libusb cannot open this device).  Device = VID 1209 / PID 0003 (see esp_run_devmode3.cmd); DeviceInterfaceGUIDs come from
# the MS OS extended-property descriptor the phone returns.  Frames: see usbfn_agent.ps1.
import ctypes, os, socket, struct, sys, time, uuid, zlib
from ctypes import wintypes as W

MAGIC = 0x5239
MAXDATA = 16000
DAEMON_PORT = 47100
DEV_GUID = '{DEE824EF-729B-4A0E-9C14-B7117D33A817}'
VIDPID = ('vid_1209&pid_0004', 'vid_1209&pid_0003', 'vid_1209&pid_0002', 'vid_1209&pid_0001')


class RemoteError(Exception):
    pass


# ---------------------------------------------------------------- WinUSB transport
class GUID(ctypes.Structure):
    _fields_ = [('Data1', ctypes.c_ulong), ('Data2', ctypes.c_ushort), ('Data3', ctypes.c_ushort), ('Data4', ctypes.c_ubyte * 8)]


def _guid(s):
    u = uuid.UUID(s)
    g = GUID()
    g.Data1, g.Data2, g.Data3 = u.time_low, u.time_mid, u.time_hi_version
    for i, b in enumerate(u.bytes[8:]):
        g.Data4[i] = b
    return g


class SP_DEVICE_INTERFACE_DATA(ctypes.Structure):
    _fields_ = [('cbSize', W.DWORD), ('InterfaceClassGuid', GUID), ('Flags', W.DWORD), ('Reserved', ctypes.c_void_p)]


class WinUsbTransport:
    def __init__(self, guid=DEV_GUID):
        self.setupapi = ctypes.WinDLL('setupapi', use_last_error=True)
        self.k32 = ctypes.WinDLL('kernel32', use_last_error=True)
        self.wu = ctypes.WinDLL('winusb', use_last_error=True)
        s, k, w = self.setupapi, self.k32, self.wu
        s.SetupDiGetClassDevsW.restype = ctypes.c_void_p
        s.SetupDiGetClassDevsW.argtypes = [ctypes.POINTER(GUID), W.LPCWSTR, W.HWND, W.DWORD]
        s.SetupDiEnumDeviceInterfaces.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(GUID), W.DWORD, ctypes.POINTER(SP_DEVICE_INTERFACE_DATA)]
        s.SetupDiGetDeviceInterfaceDetailW.argtypes = [ctypes.c_void_p, ctypes.POINTER(SP_DEVICE_INTERFACE_DATA), ctypes.c_void_p, W.DWORD, ctypes.POINTER(W.DWORD), ctypes.c_void_p]
        s.SetupDiDestroyDeviceInfoList.argtypes = [ctypes.c_void_p]
        k.CreateFileW.restype = ctypes.c_void_p
        k.CreateFileW.argtypes = [W.LPCWSTR, W.DWORD, W.DWORD, ctypes.c_void_p, W.DWORD, W.DWORD, ctypes.c_void_p]
        k.CloseHandle.argtypes = [ctypes.c_void_p]
        w.WinUsb_Initialize.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
        w.WinUsb_Free.argtypes = [ctypes.c_void_p]
        w.WinUsb_WritePipe.argtypes = [ctypes.c_void_p, ctypes.c_ubyte, ctypes.c_char_p, W.ULONG, ctypes.POINTER(W.ULONG), ctypes.c_void_p]
        w.WinUsb_ReadPipe.argtypes = [ctypes.c_void_p, ctypes.c_ubyte, ctypes.c_char_p, W.ULONG, ctypes.POINTER(W.ULONG), ctypes.c_void_p]
        w.WinUsb_SetPipePolicy.argtypes = [ctypes.c_void_p, ctypes.c_ubyte, W.ULONG, W.ULONG, ctypes.c_void_p]
        w.WinUsb_ResetPipe.argtypes = [ctypes.c_void_p, ctypes.c_ubyte]
        w.WinUsb_FlushPipe.argtypes = [ctypes.c_void_p, ctypes.c_ubyte]
        self.guid = _guid(guid)
        self.hdl = None
        self.iface = ctypes.c_void_p()
        self.rbuf = ctypes.create_string_buffer(65536)
        self.path = self._find()
        if not self.path:
            raise RemoteError('RM9 USB device not found (WinUSB interface for %s)' % '/'.join(VIDPID))
        hdl = k.CreateFileW(self.path, 0xC0000000, 3, None, 3, 0x80, None)   # RW, share RW, OPEN_EXISTING, NORMAL
        if hdl in (None, ctypes.c_void_p(-1).value):
            raise RemoteError('CreateFile failed %d (%s)' % (ctypes.get_last_error(), self.path))
        self.hdl = hdl
        if not w.WinUsb_Initialize(hdl, ctypes.byref(self.iface)):
            err = ctypes.get_last_error()
            k.CloseHandle(hdl)
            self.hdl = None
            raise RemoteError('WinUsb_Initialize failed %d' % err)
        t = W.ULONG(5000)
        one = ctypes.c_ubyte(1)
        for ep in (0x01, 0x81):
            w.WinUsb_SetPipePolicy(self.iface, ep, 3, 4, ctypes.byref(t))      # PIPE_TRANSFER_TIMEOUT
        w.WinUsb_SetPipePolicy(self.iface, 0x01, 1, 1, ctypes.byref(one))      # SHORT_PACKET_TERMINATE
        for ep in (0x01, 0x81):
            w.WinUsb_ResetPipe(self.iface, ep)
        w.WinUsb_FlushPipe(self.iface, 0x81)

    def _find(self):
        s = self.setupapi
        hdev = s.SetupDiGetClassDevsW(ctypes.byref(self.guid), None, None, 0x12)   # PRESENT | DEVICEINTERFACE
        found = []
        i = 0
        while True:
            d = SP_DEVICE_INTERFACE_DATA()
            d.cbSize = ctypes.sizeof(d)
            if not s.SetupDiEnumDeviceInterfaces(hdev, None, ctypes.byref(self.guid), i, ctypes.byref(d)):
                break
            i += 1
            need = W.DWORD(0)
            s.SetupDiGetDeviceInterfaceDetailW(hdev, ctypes.byref(d), None, 0, ctypes.byref(need), None)
            buf = ctypes.create_string_buffer(need.value)
            ctypes.cast(buf, ctypes.POINTER(W.DWORD))[0] = 8 if ctypes.sizeof(ctypes.c_void_p) == 8 else 6
            if s.SetupDiGetDeviceInterfaceDetailW(hdev, ctypes.byref(d), buf, need.value, None, None):
                found.append(ctypes.wstring_at(ctypes.addressof(buf) + 4))
        s.SetupDiDestroyDeviceInfoList(hdev)
        for p in found:
            if any(v in p.lower() for v in VIDPID):
                return p
        return None

    def send(self, frame):
        if len(frame) % 512 == 0:
            frame += b'\0'
        done = W.ULONG(0)
        if not self.wu.WinUsb_WritePipe(self.iface, 0x01, frame, len(frame), ctypes.byref(done), None):
            raise RemoteError('WinUsb_WritePipe failed %d' % ctypes.get_last_error())

    def recv(self, timeout_s):
        """one transfer = one frame; returns bytes or None on timeout"""
        t = W.ULONG(int(timeout_s * 1000))
        self.wu.WinUsb_SetPipePolicy(self.iface, 0x81, 3, 4, ctypes.byref(t))
        got = W.ULONG(0)
        if not self.wu.WinUsb_ReadPipe(self.iface, 0x81, self.rbuf, 65536, ctypes.byref(got), None):
            e = ctypes.get_last_error()
            if e in (121, 1460):      # ERROR_SEM_TIMEOUT / ERROR_TIMEOUT
                return None
            raise RemoteError('WinUsb_ReadPipe failed %d' % e)
        return self.rbuf.raw[:got.value]

    def close(self):
        if self.hdl:
            self.wu.WinUsb_Free(self.iface)
            self.k32.CloseHandle(self.hdl)
            self.hdl = None


class _DkId(ctypes.Structure):
    _fields_ = [('DeviceID', ctypes.c_wchar * 200), ('InstanceID', ctypes.c_wchar * 200)]


class _DkInfo(ctypes.Structure):
    _fields_ = [('ID', _DkId), ('FilterID', ctypes.c_uint64), ('Port', ctypes.c_uint64), ('Speed', ctypes.c_uint64), ('Desc', ctypes.c_ubyte * 18)]


class _DkResult(ctypes.Structure):
    _fields_ = [('BytesTransferred', ctypes.c_uint64), ('UsbdStatus', ctypes.c_uint32)]


class _DkReq(ctypes.Structure):
    _fields_ = [('EndpointAddress', ctypes.c_uint64), ('Buffer', ctypes.c_void_p), ('BufferLength', ctypes.c_uint64), ('TransferType', ctypes.c_uint64),
                ('IsoSize', ctypes.c_uint64), ('IsoArray', ctypes.c_void_p), ('Result', _DkResult)]


class _Ov(ctypes.Structure):
    _fields_ = [('Internal', ctypes.c_void_p), ('InternalHigh', ctypes.c_void_p), ('Offset', ctypes.c_uint32), ('OffsetHigh', ctypes.c_uint32), ('hEvent', ctypes.c_void_p)]


class UsbdkTransport:
    """UsbDk API directly through UsbDkHelper.dll (libusb 1.0.27 refuses to use it here): bulk OUT 0x01 / IN 0x81.  UsbDk must be installed (and the PC rebooted once)."""
    def __init__(self):
        rt = r'C:\Program Files\UsbDk Runtime Library'
        self.d = ctypes.WinDLL(os.path.join(rt, 'UsbDkHelper.dll'), use_last_error=True)
        self.k = ctypes.WinDLL('kernel32', use_last_error=True)
        d, k = self.d, self.k
        d.UsbDk_StartRedirect.restype = ctypes.c_void_p
        d.UsbDk_StartRedirect.argtypes = [ctypes.POINTER(_DkId)]
        d.UsbDk_GetRedirectorSystemHandle.restype = ctypes.c_void_p
        d.UsbDk_GetRedirectorSystemHandle.argtypes = [ctypes.c_void_p]
        d.UsbDk_ReadPipe.argtypes = [ctypes.c_void_p, ctypes.POINTER(_DkReq), ctypes.POINTER(_Ov)]
        d.UsbDk_WritePipe.argtypes = [ctypes.c_void_p, ctypes.POINTER(_DkReq), ctypes.POINTER(_Ov)]
        d.UsbDk_AbortPipe.argtypes = [ctypes.c_void_p, ctypes.c_uint64]
        d.UsbDk_StopRedirect.argtypes = [ctypes.c_void_p]
        k.CreateEventW.restype = ctypes.c_void_p
        k.CreateEventW.argtypes = [ctypes.c_void_p, W.BOOL, W.BOOL, W.LPCWSTR]
        k.WaitForSingleObject.argtypes = [ctypes.c_void_p, W.DWORD]
        k.ResetEvent.argtypes = [ctypes.c_void_p]
        p = ctypes.POINTER(_DkInfo)()
        n = ctypes.c_ulong(0)
        if not d.UsbDk_GetDevicesList(ctypes.byref(p), ctypes.byref(n)):
            raise RemoteError('UsbDk_GetDevicesList failed (UsbDk not installed or PC not rebooted?)')
        target = None
        for i in range(n.value):
            if bytes(p[i].Desc[8:10]) == b'\x09\x12':       # idVendor 0x1209
                target = _DkId()
                ctypes.memmove(ctypes.byref(target), ctypes.byref(p[i].ID), ctypes.sizeof(_DkId))
        d.UsbDk_ReleaseDevicesList(p)
        if target is None:
            raise RemoteError('RM9 USB device not found (UsbDk, VID 1209)')
        self.red = d.UsbDk_StartRedirect(ctypes.byref(target))
        if not self.red:
            raise RemoteError('UsbDk_StartRedirect failed %d' % ctypes.get_last_error())
        self.sys = d.UsbDk_GetRedirectorSystemHandle(self.red)
        self.evr = k.CreateEventW(None, True, False, None)       # separate events: reads and writes run concurrently (packet relay)
        self.evw = k.CreateEventW(None, True, False, None)
        self.rbuf = ctypes.create_string_buffer(65536)
        self.path = 'usbdk:' + target.DeviceID

    def _xfer(self, write, ep, buf, length, timeout_ms):
        req = _DkReq()
        req.EndpointAddress = ep
        req.Buffer = ctypes.cast(buf, ctypes.c_void_p).value
        req.BufferLength = length
        req.TransferType = 1                       # bulk
        ov = _Ov()
        ev = self.evw if write else self.evr
        ov.hEvent = ev
        self.k.ResetEvent(ev)
        fn = self.d.UsbDk_WritePipe if write else self.d.UsbDk_ReadPipe
        r = fn(self.red, ctypes.byref(req), ctypes.byref(ov))     # 0 failure, 1 done, 2 async
        if r == 0:
            raise RemoteError('UsbDk transfer submit failed ep=0x%02x' % ep)
        if r == 2:
            if self.k.WaitForSingleObject(ev, timeout_ms) != 0:
                self.d.UsbDk_AbortPipe(self.red, ep)
                self.k.WaitForSingleObject(ev, 5000)
                return None
        if req.Result.UsbdStatus != 0:
            raise RemoteError('UsbDk transfer ep=0x%02x usbd status 0x%x' % (ep, req.Result.UsbdStatus))
        return req.Result.BytesTransferred

    def send(self, frame):
        if len(frame) % 512 == 0:
            frame += bytes(1)
        buf = ctypes.create_string_buffer(frame, len(frame))
        if self._xfer(True, 0x01, buf, len(frame), 5000) is None:
            raise RemoteError('bulk OUT timeout')

    def recv(self, timeout_s):
        n = self._xfer(False, 0x81, self.rbuf, 65536, int(timeout_s * 1000))
        if n is None:
            return None
        return self.rbuf.raw[:n]

    def close(self):
        self.d.UsbDk_StopRedirect(self.red)


class TcpTransport:
    def __init__(self, port):
        self.s = socket.create_connection(('127.0.0.1', port), timeout=10)
        self.buf = b''

    def send(self, frame):
        self.s.sendall(frame)

    def _need(self, n, timeout_s):
        self.s.settimeout(timeout_s)
        while len(self.buf) < n:
            try:
                d = self.s.recv(65536)
            except socket.timeout:
                return False
            if not d:
                raise RemoteError('connection closed')
            self.buf += d
        return True

    def recv(self, timeout_s):
        if not self._need(12, timeout_s):
            return None
        plen = struct.unpack_from('<I', self.buf, 8)[0]
        if not self._need(12 + plen, timeout_s):
            return None
        f, self.buf = self.buf[:12 + plen], self.buf[12 + plen:]
        return f

    def close(self):
        self.s.close()


# ---------------------------------------------------------------- link
class Link:
    def __init__(self, tcp=None, wait=0, usbdk=None):
        if usbdk is None:
            usbdk = not os.environ.get('RM9_WINUSB')      # WinUSB cannot start on this device (0xC0000182): UsbDk is the default
        end = time.time() + wait
        while True:
            try:
                if tcp:
                    self.t = TcpTransport(tcp)
                else:
                    try:
                        self.t = TcpTransport(DAEMON_PORT)       # `rm9link.py serve` keeps the USB redirect open (every open/close of UsbDk resets the device)
                    except OSError:
                        self.t = UsbdkTransport() if usbdk else WinUsbTransport()
                break
            except (RemoteError, OSError):
                if time.time() >= end:
                    raise
                time.sleep(1)
        self.id = int(time.time()) & 0xFFFFFF

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()

    def close(self):
        self.t.close()

    def _send(self, typ, payload=b'', flags=0):
        self.id += 1
        self.t.send(struct.pack('<HBBII', MAGIC, typ, flags, self.id, len(payload)) + payload)
        return self.id

    def _recv(self, rid, timeout_s):
        """next frame for request rid -> (type, payload); stale frames from older requests are dropped"""
        end = time.time() + timeout_s
        while True:
            left = end - time.time()
            if left <= 0:
                raise RemoteError('timeout waiting for the phone')
            f = self.t.recv(min(left, 5))
            if f is None:
                continue
            if len(f) < 12:
                continue
            magic, typ, flags, fid, plen = struct.unpack_from('<HBBII', f, 0)
            if magic != MAGIC or fid != rid:
                continue
            return typ, f[12:12 + plen]

    def ping(self, data=b'ping', timeout_s=10):
        t0 = time.time()
        rid = self._send(1, data)
        typ, pl = self._recv(rid, timeout_s)
        if typ != 0x81 or pl != data:
            raise RemoteError('bad pong %r' % pl)
        return time.time() - t0

    def ver(self, timeout_s=10):
        rid = self._send(6)
        typ, pl = self._recv(rid, timeout_s)
        return pl.decode('utf-8', 'replace')

    def exec(self, cmd, timeout_s=60):
        """run `cmd /c <cmd>` as SYSTEM on the phone -> (exit code, output bytes)"""
        rid = self._send(2, ('%d\n%s' % (timeout_s, cmd)).encode())
        out = b''
        while True:
            typ, pl = self._recv(rid, timeout_s + 30)
            if typ == 0x82:
                out += pl
            elif typ == 0x83:
                return struct.unpack('<i', pl)[0], out
            elif typ == 0x8F:
                raise RemoteError(pl.decode('utf-8', 'replace'))

    def put(self, local, remote, progress=None):
        rp = remote.encode()
        size = os.path.getsize(local)
        done = 0
        with open(local, 'rb') as f:
            first = True
            while True:
                chunk = f.read(MAXDATA - 2 - len(rp))
                if not chunk and not first:
                    break
                rid = self._send(3, struct.pack('<H', len(rp)) + rp + chunk, 1 if first else 0)
                first = False
                typ, pl = self._recv(rid, 30)
                st = struct.unpack_from('<i', pl, 0)[0]
                if typ != 0x80 or st != 0:
                    raise RemoteError('put failed: %s' % pl[4:].decode('utf-8', 'replace'))
                done += len(chunk)
                if progress:
                    progress(done, size)
                if not chunk:
                    break
        return size

    def get(self, remote, local):
        rid = self._send(4, remote.encode())
        total = 0
        with open(local, 'wb') as f:
            while True:
                typ, pl = self._recv(rid, 30)
                if typ == 0x84:
                    f.write(pl)
                    total += len(pl)
                elif typ == 0x85:
                    n = struct.unpack('<Q', pl)[0]
                    if n != total:
                        raise RemoteError('size mismatch %d != %d' % (n, total))
                    return total
                elif typ == 0x8F:
                    raise RemoteError(pl.decode('utf-8', 'replace'))

    def reboot(self):
        rid = self._send(5)
        return self._recv(rid, 10)


class _WintunPc:
    """Wintun adapter on the PC (needs an elevated process): IP packets <-> frames 0x11 (to the phone) / 0x91 (from the phone)."""
    def __init__(self, name='rm9usb', ip='192.168.x.x', mask='255.255.255.0'):
        dll = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'third_party', 'wintun', 'amd64', 'wintun.dll')
        w = self.w = ctypes.WinDLL(os.path.abspath(dll), use_last_error=True)
        w.WintunCreateAdapter.restype = ctypes.c_void_p
        w.WintunCreateAdapter.argtypes = [W.LPCWSTR, W.LPCWSTR, ctypes.POINTER(GUID)]
        w.WintunStartSession.restype = ctypes.c_void_p
        w.WintunStartSession.argtypes = [ctypes.c_void_p, W.DWORD]
        w.WintunGetReadWaitEvent.restype = ctypes.c_void_p
        w.WintunGetReadWaitEvent.argtypes = [ctypes.c_void_p]
        w.WintunReceivePacket.restype = ctypes.c_void_p
        w.WintunReceivePacket.argtypes = [ctypes.c_void_p, ctypes.POINTER(W.DWORD)]
        w.WintunReleaseReceivePacket.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        w.WintunAllocateSendPacket.restype = ctypes.c_void_p
        w.WintunAllocateSendPacket.argtypes = [ctypes.c_void_p, W.DWORD]
        w.WintunSendPacket.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        k = self.k = ctypes.WinDLL('kernel32', use_last_error=True)
        k.WaitForSingleObject.argtypes = [ctypes.c_void_p, W.DWORD]
        g = _guid('{5d6f0a1e-7c33-4b0f-9f55-2f6b1c0d9a43}')
        self.ad = w.WintunCreateAdapter(name, 'RM9', ctypes.byref(g))
        if not self.ad:
            raise RemoteError('WintunCreateAdapter failed %d (needs an elevated process)' % ctypes.get_last_error())
        self.sess = w.WintunStartSession(self.ad, 0x400000)
        if not self.sess:
            raise RemoteError('WintunStartSession failed %d' % ctypes.get_last_error())
        self.ev = w.WintunGetReadWaitEvent(self.sess)
        self.name, self.ip, self.mask = name, ip, mask

    def configure(self):
        import subprocess
        subprocess.run(['netsh', 'interface', 'ip', 'set', 'address', 'name=' + self.name, 'static', self.ip, self.mask], capture_output=True)

    def read(self):
        """-> packet bytes (waits up to 0.5 s; None on timeout)"""
        n = W.DWORD(0)
        p = self.w.WintunReceivePacket(self.sess, ctypes.byref(n))
        if not p:
            self.k.WaitForSingleObject(self.ev, 500)
            return None
        data = ctypes.string_at(p, n.value)
        self.w.WintunReleaseReceivePacket(self.sess, p)
        return data

    def write(self, pkt):
        p = self.w.WintunAllocateSendPacket(self.sess, len(pkt))
        if p:
            ctypes.memmove(p, pkt, len(pkt))
            self.w.WintunSendPacket(self.sess, p)


def serve(net=False):
    """Daemon: owns the USB link (UsbDk redirect stays open), relays frames for local clients on 127.0.0.1:DAEMON_PORT and, with net=True (elevated), bridges IP packets to a Wintun adapter."""
    import threading
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(('127.0.0.1', DAEMON_PORT))
    srv.listen(4)
    usb = None
    slock = threading.Lock()          # sends to the phone
    rlock = threading.Lock()          # receives from the phone
    cur = {'c': None}
    last_rx = [time.time()]
    last_err = ['', '']
    wt = None

    def log(m):
        line = '%s %s' % (time.strftime('%H:%M:%S'), m)
        print(line, flush=True)
        try:
            with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'winboot', 'rm9link_daemon.log'), 'a', encoding='utf-8') as f:
                f.write(line + chr(10))
        except Exception:
            pass

    if net:
        wt = _WintunPc()
        wt.configure()
        log('wintun adapter %s up (%s)' % (wt.name, wt.ip))

    def usb_open():
        nonlocal usb
        while usb is None:
            try:
                usb = UsbdkTransport()
                log('usb open: ' + usb.path)
            except Exception as e:
                if str(e) != last_err[0]:
                    log('usb open failed: %s' % e)
                    last_err[0] = str(e)
                time.sleep(1)

    def usb_send(fr):
        if usb is None:
            return False
        try:
            with slock:
                usb.send(fr)
            return True
        except Exception as e:
            if str(e) != last_err[0] + 'S':
                log('usb send error: %r' % e)
                last_err[0] = str(e) + 'S'
            return False

    def pump():
        nonlocal usb
        while True:
            if usb is None:
                time.sleep(0.2)
                continue
            try:
                with rlock:
                    f = usb.recv(0.3)
            except Exception as e:
                if str(e) != last_err[1]:
                    log('usb recv error: %r' % e)
                    last_err[1] = str(e)
                try:
                    usb.close()
                except Exception:
                    pass
                usb = None
                time.sleep(3)            # let the device finish its enumeration before the next redirect
                usb_open()
                last_rx[0] = time.time()
                continue
            if not f or len(f) < 12:
                if time.time() - last_rx[0] > 8 and usb is not None:       # the agent sends a heartbeat every 2 s: silence = the device re-enumerated
                    log('no frames for 8 s: reopening the USB redirect')
                    try:
                        usb.close()
                    except Exception:
                        pass
                    usb = None
                    usb_open()
                    last_rx[0] = time.time()
                continue
            last_rx[0] = time.time()
            if f[2] == 0x92:
                continue
            if f[2] == 0x91 and wt:
                plen = struct.unpack_from('<I', f, 8)[0]
                wt.write(f[12:12 + plen])
                continue
            if cur['c']:
                try:
                    cur['c'].sendall(f)
                except OSError:
                    cur['c'] = None

    def netrx():
        cnt = 0
        while True:
            pkt = wt.read()
            if pkt:
                if pkt[0] >> 4 == 4:
                    cnt += 1
                if pkt[0] >> 4 == 4 and (cnt <= 20 or pkt[9] == 1) and len(pkt) >= 20:
                    log('net PC->phone #%d len=%d proto=%d %s > %s' % (cnt, len(pkt), pkt[9], '.'.join(str(b) for b in pkt[12:16]), '.'.join(str(b) for b in pkt[16:20])))
            if pkt and usb is not None and len(pkt) <= 15000:
                ok = usb_send(struct.pack('<HBBII', MAGIC, 0x11, 0, 0, len(pkt)) + pkt)
                if not ok:
                    log('  send failed')

    def client(c):
        buf = b''
        cur['c'] = c
        try:
            while True:
                d = c.recv(65536)
                if not d:
                    break
                buf += d
                while len(buf) >= 12:
                    plen = struct.unpack_from('<I', buf, 8)[0]
                    if len(buf) < 12 + plen:
                        break
                    fr, buf = buf[:12 + plen], buf[12 + plen:]
                    usb_send(fr)
        finally:
            if cur['c'] is c:
                cur['c'] = None
            c.close()

    threading.Thread(target=usb_open, daemon=True).start()
    threading.Thread(target=pump, daemon=True).start()
    if wt:
        threading.Thread(target=netrx, daemon=True).start()
    log('daemon listening on %d' % DAEMON_PORT)
    while True:
        c, _ = srv.accept()
        threading.Thread(target=client, args=(c,), daemon=True).start()


def main(argv):
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass
    tcp = None
    if len(argv) > 1 and argv[0] == '--tcp':
        tcp = int(argv[1])
        argv = argv[2:]
    if not argv:
        print(__doc__ or 'usage: rm9link.py ping|ver|exec|put|get|reboot|wait')
        return 2
    cmd, rest = argv[0], argv[1:]
    if cmd == 'serve':
        serve(net='--net' in rest)
        return 0
    wait = 0
    if cmd == 'wait':
        wait, cmd = 3600, 'ping'
    with Link(tcp=tcp, wait=wait) as L:
        if cmd == 'ping':
            print('pong %.1f ms' % (L.ping() * 1000))
        elif cmd == 'ver':
            print(L.ver())
        elif cmd == 'exec':
            to = 60
            if rest and rest[0] == '-t':
                to, rest = int(rest[1]), rest[2:]
            code, out = L.exec(' '.join(rest), to)
            sys.stdout.write(out.decode('utf-8', 'replace'))
            return code
        elif cmd == 'put':
            t0 = time.time()
            n = L.put(rest[0], rest[1])
            print('%d bytes in %.2f s' % (n, time.time() - t0))
        elif cmd == 'get':
            t0 = time.time()
            n = L.get(rest[0], rest[1])
            print('%d bytes in %.2f s' % (n, time.time() - t0))
        elif cmd == 'reboot':
            print(L.reboot())
        else:
            print('unknown command', cmd)
            return 2
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
