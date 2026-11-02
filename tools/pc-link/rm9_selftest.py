# Waits for the phone's agent, then runs ping / ver / exec / put / get checks; log to winboot/rm9_selftest.log
import os, sys, time, hashlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rm9link
log = r'<RM9_WORKDIR>\winboot\rm9_selftest.log'
def L(m):
    with open(log, 'a', encoding='utf-8') as f:
        f.write('%s %s\n' % (time.strftime('%H:%M:%S'), m))
L('--- start')
end = time.time() + 1500
last = ''
while time.time() < end:
    try:
        L('trying to open')
        with rm9link.Link(wait=0, usbdk=True) as k:
            L('opened: ' + k.t.path)
            L('ping %.1f ms' % (k.ping() * 1000))
            L('ver: ' + k.ver())
            c, o = k.exec('ver & whoami & hostname', 20)
            L('exec -> %d %r' % (c, o))
            data = os.urandom(1000000)
            open(r'C:\Users\<user>\AppData\Local\Temp\st.bin', 'wb').write(data)
            t0 = time.time()
            k.put(r'C:\Users\<user>\AppData\Local\Temp\st.bin', r'C:\rm9\st.bin')
            L('put 1MB %.2f s' % (time.time() - t0))
            t0 = time.time()
            k.get(r'C:\rm9\st.bin', r'C:\Users\<user>\AppData\Local\Temp\st_back.bin')
            L('get 1MB %.2f s' % (time.time() - t0))
            L('compare ok=%s' % (open(r'C:\Users\<user>\AppData\Local\Temp\st_back.bin', 'rb').read() == data))
            L('SELFTEST DONE')
            break
    except Exception as e:
        m = repr(e)
        if m != last:
            L('error: ' + m); last = m
        time.sleep(2)
