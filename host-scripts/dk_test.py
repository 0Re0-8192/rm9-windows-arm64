import sys, time, ctypes
sys.path.insert(0, r'<RM9_WORKDIR>\refs')
import rm9link as R
print('open', flush=True)
t = R.UsbdkTransport()
print('opened', t.path, flush=True)
for i in range(6):
    time.sleep(2)
    try:
        n = t.recv(1.0)
        print(i, 'recv ->', None if n is None else len(n), flush=True)
    except Exception as e:
        print(i, 'recv err', e, ctypes.get_last_error(), flush=True)
t.close()
print('closed', flush=True)
