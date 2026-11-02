"""mk_mcfg.py <out.aml> : MCFG for the SM8650 PCIe0 root complex.  ECAM = the DW iATU CFG window at 0x60100000 (1 MB) = bus 1 of segment 0.
MuChain (PcieProbe, PCIE.TXT) programs the iATU in CFG shift mode so that dev<<15 | fn<<12 | reg reach bus 1 (only device 0 is forwarded to the endpoint, the rest answers UR)."""
import struct, sys
body = struct.pack("<8x")                                   # reserved
body += struct.pack("<QHBBI", 0x60000000, 0, 1, 1, 0)      # base of bus 0 (ECAM base, the root port DBI would be bus 0 dev 0), segment 0, start bus 1, end bus 1, reserved
hdr = b"MCFG" + struct.pack("<I", 36 + len(body)) + bytes([1, 0]) + b"QCOM  " + b"QCOMEDK2" + struct.pack("<I", 0x8650) + b"QCOM" + struct.pack("<I", 1)
t = bytearray(hdr + body)
t[9] = (-sum(t)) & 0xFF
open(sys.argv[1], "wb").write(bytes(t))
print("MCFG %d bytes" % len(t))
