"""Resume a PUT: append local[offset:] to the remote file (the remote file must be exactly `offset` bytes long).
usage: rm9put_resume.py <local> <remote> <offset|auto>      'auto' reads the remote size with `dir`.
Progress is written to <local>.put.log (one line per 256 MiB)."""
import os, re, struct, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rm9link as R

local, remote, off = sys.argv[1], sys.argv[2], sys.argv[3]
log = open(local + '.put.log', 'a', buffering=1)


def L(m):
    log.write('%s %s\n' % (time.strftime('%H:%M:%S'), m))


with R.Link() as link:
    if off == 'auto':
        code, out = link.exec('for %I in ("' + remote + '") do @echo SIZE=%~zI', 30)
        m = re.search(rb'SIZE=(\d+)', out)
        off = int(m.group(1))
    else:
        off = int(off)
    size = os.path.getsize(local)
    L('start remote=%s offset=%d of %d' % (remote, off, size))
    rp = remote.encode()
    step = R.MAXDATA - 2 - len(rp)
    done = off
    t0 = time.time()
    last = done
    with open(local, 'rb') as f:
        f.seek(off)
        while True:
            chunk = f.read(step)
            if not chunk:
                break
            rid = link._send(3, struct.pack('<H', len(rp)) + rp + chunk, 0)      # flags 0 = append
            typ, pl = link._recv(rid, 30)
            st = struct.unpack_from('<i', pl, 0)[0]
            if typ != 0x80 or st != 0:
                L('FAILED at %d: %s' % (done, pl[4:].decode('utf-8', 'replace')))
                sys.exit(1)
            done += len(chunk)
            if done - last >= 256 * 1024 * 1024:
                last = done
                L('%d / %d (%.1f MB/s)' % (done, size, (done - off) / 1e6 / (time.time() - t0)))
    L('DONE %d bytes, %.0f s' % (done, time.time() - t0))
