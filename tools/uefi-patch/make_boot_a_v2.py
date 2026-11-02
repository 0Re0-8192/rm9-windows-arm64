"""Build the slot-a launcher boot image: boot header v2 = Mu UEFI kernel + the platform dtb (taken from vendor_boot_b), so ABL needs no vendor_boot_a (which is an ext4 image in this device's setup)."""
import struct, subprocess, sys
W = '<RM9_WORKDIR>/winboot/slota/'
mu = open('<RM9_WORKDIR>/out/Mu-pcie-rp5.img', 'rb').read()
ksz = struct.unpack('<I', mu[8:12])[0]; rsz = struct.unpack('<I', mu[12:16])[0]
assert mu[:8] == b'ANDROID!' and struct.unpack('<I', mu[40:44])[0] == 4
open(W + 'mu_kernel.bin', 'wb').write(mu[4096:4096 + ksz])
roff = 4096 + (ksz + 4095) // 4096 * 4096
open(W + 'mu_ramdisk.bin', 'wb').write(mu[roff:roff + rsz])
print('ramdisk', rsz, mu[roff:roff + rsz])
vb = open(W + 'vendor_boot_b_head20.img', 'rb').read()
assert vb[:8] == b'VNDRBOOT'
ver, page, kaddr, raddr, vrsz = struct.unpack('<5I', vb[8:28])
hdr = struct.unpack('<I', vb[2096:2100])[0]; dsz = struct.unpack('<I', vb[2100:2104])[0]
def up(n): return (n + page - 1) // page * page
doff = up(hdr) + up(vrsz)
print('vendor_boot v%d page %d header %d vendor_ramdisk %d dtb %d @ %d' % (ver, page, hdr, vrsz, dsz, doff))
open(W + 'platform.dtb', 'wb').write(vb[doff:doff + dsz])
print('kernel', ksz, 'dtb', dsz)
