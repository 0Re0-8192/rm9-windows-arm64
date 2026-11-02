"""vhdx_make_patch.py <new file> <remote block-hash file> <patch out> [block MB]
Compares <new file> with the MD5-per-block list the phone computed for its current copy (vhdx_blockhash.ps1) and writes a patch (see vhdx_apply_patch.ps1)
that turns the phone's file into <new file>.   Also: vhdx_make_patch.py hash <file> <out> [block MB]  writes the same hash list for a local file."""
import hashlib, struct, sys

BLOCK_MB = 4


def hashes(path, bs):
    out = []
    with open(path, 'rb') as f:
        while True:
            b = f.read(bs)
            if not b:
                break
            out.append(hashlib.md5(b).digest())
    return out


def main():
    global BLOCK_MB
    if sys.argv[1] == 'hash':
        bs = (int(sys.argv[4]) if len(sys.argv) > 4 else BLOCK_MB) * 1024 * 1024
        open(sys.argv[3], 'wb').write(b''.join(hashes(sys.argv[2], bs)))
        return
    new, rem, out = sys.argv[1:4]
    if len(sys.argv) > 4:
        BLOCK_MB = int(sys.argv[4])
    bs = BLOCK_MB * 1024 * 1024
    rh = open(rem, 'rb').read()
    rlist = [rh[i:i + 16] for i in range(0, len(rh), 16)]
    import os
    size = os.path.getsize(new)
    changed = []
    with open(new, 'rb') as f:
        i = 0
        while True:
            b = f.read(bs)
            if not b:
                break
            if i >= len(rlist) or hashlib.md5(b).digest() != rlist[i]:
                changed.append((i * bs, b))
            i += 1
    with open(out, 'wb') as o:
        o.write(struct.pack('<QI', size, len(changed)))
        for off, b in changed:
            o.write(struct.pack('<QI', off, len(b)))
            o.write(b)
    print('blocks total %d, changed %d (%.1f MB), patch %d bytes' % (i, len(changed), sum(len(b) for _, b in changed) / 1e6, os.path.getsize(out)))


main()
