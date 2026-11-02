"""mk_iort_msi.py <out.aml> : minimal IORT for PCIe0 MSI through the GICv3 ITS (no SMMU nodes).
node 0 = ITS group (ITS id 0, the MADT GIC ITS at 0x17140000); node 1 = PCI root complex segment 0 with one ID mapping RID 0x0100 (bus 1 dev 0 fn 0) -> ITS DeviceID 0x1401
(DT: msi-map = <0x100 &its 0x1401 1>).  The RC's DeviceIDs come from the PARF BDF-to-SID translation that MuChain programs (PARF+0x2054 = 0x01000100)."""
import struct, sys
its_off = 48
its = struct.pack("<BHBIII", 0, 24, 0, 0, 0, 0)        # type, length, revision, (id), mapping count, mapping offset  -> 16 bytes
its = struct.pack("<BHBIII", 0, 24, 0, 0, 0, 0) + struct.pack("<II", 1, 0)   # ITS count 1, ITS id 0  -> 24 bytes
rc_hdr_len = 16 + 8 + 4 + 4
rc_len = rc_hdr_len + 20                                # one ID mapping
rc = struct.pack("<BHBIII", 2, rc_len, 0, 0, 1, rc_hdr_len)
rc += struct.pack("<IBBHB", 1, 0, 0, 0, 0)[:8]          # cache coherent = 1, alloc hints 0, reserved, memory access flags 0   (8 bytes)
rc += struct.pack("<I", 0)                              # ATS attribute: not supported
rc += struct.pack("<I", 0)                              # PCI segment 0
rc += struct.pack("<IIIII", 0x0, 0x100, 0x1301, its_off, 0)   # RIDs 0..0x100: the root port (RID 0) gets DeviceID 0x1301, the endpoint (RID 0x100) keeps 0x1401 as the PARF BDF->SID translation gives it   # input base, number of IDs - 1, output base, output reference (offset of the ITS group node), flags
assert len(rc) == rc_len, (len(rc), rc_len)
body = struct.pack("<III", 2, 48, 0) + its + rc
hdr = b"IORT" + struct.pack("<I", 36 + len(body)) + bytes([0, 0]) + b"QCOM  " + b"QCOMEDK2" + struct.pack("<I", 0x8650) + b"QCOM" + struct.pack("<I", 1)
t = bytearray(hdr + body)
t[9] = (-sum(t)) & 0xFF
open(sys.argv[1], "wb").write(bytes(t))
print("IORT %d bytes, ITS group at 0x%x, RC at 0x%x" % (len(t), 48, 48 + len(its)))
