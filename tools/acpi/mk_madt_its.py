"""mk_madt_its.py <in APIC.aml> <out.aml> : append a GIC ITS entry (ITS id 0, base 0x17140000) to the MADT."""
import struct, sys
t = bytearray(open(sys.argv[1], "rb").read())
assert t[:4] == b"APIC"
t += struct.pack("<BBHIQI", 0x0F, 20, 0, 0, 0x17140000, 0)
t[4:8] = struct.pack("<I", len(t))
t[9] = 0
t[9] = (-sum(t)) & 0xFF
open(sys.argv[2], "wb").write(bytes(t))
print("MADT %d bytes (+ITS)" % len(t))
