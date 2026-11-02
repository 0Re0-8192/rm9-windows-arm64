#!/usr/bin/env python3
"""Add UFSS(): snapshot the UFS host controller registers (0x1D84000) from AML into RAMCON (0xD7FF2000), only when they changed,
plus the UTRD/UPIU (opcode, LUN, tag, CDB) of the lowest and the highest in-flight slot.
Called from UFS0._STA and URS0/USB0._STA (the kernel evaluates them regularly) -> shows what storufs does to the controller.

  instrument_ufs_regs.py DSDT_dbg.dsl DSDT_dbg2.dsl

Layout at 0xD7FF2000 (u32):  [0]=UFSS calls  [1]=snapshots stored  [4..]= 16 slots x 48 dwords, slot = (stored-1)&15, dwords:
  0 Timer  1 HCE  2 HCS  3 IS  4 IE  5 UECPA  6 UECDL  7 UECN  8 UECT  9 UTRLBA 10 UTRLBAU 11 UTRLDBR 12 UTRLRSR 13 UICCMD 14 UCMDARG1 15 UCMDARG2
  16..26 lowest in-flight slot : slot, UTRD.DW0, UTRD.DW2, UCD lo, UCD hi, UPIU.DW0, UPIU.DW1, UPIU.DW2, CDB.DW0, CDB.DW1, CDB.DW2   (slot 0xFFFFFFFF = none)
  27..37 highest in-flight slot: same
"""
import sys

src = open(sys.argv[1], encoding="utf-8").read()
assert "UFSS" not in src
SLOT_DW = 48
NSLOT = 16

REGS = [  # (field name, offset)
    ("HCE_", 0x34), ("HCS_", 0x30), ("IS__", 0x20), ("IE__", 0x24), ("ECPA", 0x38), ("ECDL", 0x3C), ("ECN_", 0x40),
    ("ECT_", 0x44), ("TRLB", 0x50), ("TRLU", 0x54), ("TRDB", 0x58), ("TRRS", 0x60), ("UIC_", 0x90), ("UA1_", 0x94),
    ("UA2_", 0x98),
]

hc = ["        OperationRegion (UHC0, SystemMemory, 0x01D84000, 0xA0)", "        Field (UHC0, DWordAcc, NoLock, Preserve)", "        {"]
pos = 0
for name, off in sorted(REGS, key=lambda r: r[1]):
    if off > pos:
        hc.append("            Offset (0x%02X)," % off)
    hc.append("            %s,   32," % name)
    pos = off + 4
hc[-1] = hc[-1].rstrip(",")
hc.append("        }")

sn = ["        OperationRegion (SNP0, SystemMemory, 0xD7FF2000, 0x%X)" % (0x10 + NSLOT * SLOT_DW * 4),
      "        Field (SNP0, DWordAcc, NoLock, Preserve)", "        {",
      "            SCLL,   32,", "            STOR,   32,", "            Offset (0x10),"]
for s in range(NSLOT):
    for i in range(SLOT_DW):
        last = (s == NSLOT - 1 and i == SLOT_DW - 1)
        sn.append("            Q%X%02X,   32%s" % (s, i, "" if last else ","))
sn.append("        }")

pv = "\n".join("        Name (V%02d_, 0xFFFFFFFF)" % k for k in range(15))
ev = "\n".join("        Name (E%02d_, 0xFFFFFFFF)" % k for k in range(22))


def extract(prefix):
    """method reading the UTRD + UPIU of slot Arg0 into E<base>.. names; prefix = first E index (0 or 11)"""
    e = lambda k: "E%02d_" % (prefix + k)
    return """
        Method (UFX%s, 1, NotSerialized)
        {
            %s = 0xFFFFFFFF
            Local0 = (TRLU << 32) | TRLB
            If ((Local0 != Zero) && (Local0 < 0x1000000000))
            {
                OperationRegion (TRD%s, SystemMemory, Local0 + (Arg0 << 5), 0x20)
                Field (TRD%s, DWordAcc, NoLock, Preserve)
                {
                    T0__,   32,
                    T1__,   32,
                    T2__,   32,
                    T3__,   32,
                    T4__,   32,
                    T5__,   32,
                    T6__,   32,
                    T7__,   32
                }
                %s = Arg0
                %s = T0__
                %s = T2__
                %s = T4__
                %s = T5__
                Local1 = (T5__ << 32) | T4__
                If ((Local1 != Zero) && (Local1 < 0x1000000000))
                {
                    OperationRegion (UCD%s, SystemMemory, Local1, 0x20)
                    Field (UCD%s, DWordAcc, NoLock, Preserve)
                    {
                        U0__,   32,
                        U1__,   32,
                        U2__,   32,
                        U3__,   32,
                        C0__,   32,
                        C1__,   32,
                        C2__,   32,
                        C3__,   32
                    }
                    %s = U0__
                    %s = U1__
                    %s = U2__
                    %s = C0__
                    %s = C1__
                    %s = C2__
                }
            }
        }
""" % ("L" if prefix == 0 else "H", e(0), "L" if prefix == 0 else "H", "L" if prefix == 0 else "H",
       e(0), e(1), e(2), e(3), e(4), "L" if prefix == 0 else "H", "L" if prefix == 0 else "H",
       e(5), e(6), e(7), e(8), e(9), e(10))


diff = " | ".join("(%s ^ V%02d_)" % (REGS[k][0], k) for k in range(15))
ifs = []
for s in range(NSLOT):
    body = ["                Q%X00 = Local2" % s]
    for i, (name, _) in enumerate(REGS):
        body.append("                Q%X%02X = %s" % (s, i + 1, name))
    for k in range(22):
        body.append("                Q%X%02X = E%02d_" % (s, 16 + k, k))
    ifs.append("            If (Local1 == 0x%02X)\n            {\n%s\n            }" % (s, "\n".join(body)))
save = "\n".join("            V%02d_ = %s" % (k, REGS[k][0]) for k in range(15))

method = """
        Method (UFSS, 0, NotSerialized)
        {
            SCLL = SCLL + 1
            Local0 = %s
            If (Local0 != Zero)
            {
                Local2 = Timer & 0xFFFFFFFF
                Local1 = STOR & 0x0F
                E00_ = 0xFFFFFFFF
                E11_ = 0xFFFFFFFF
                If (TRDB != Zero)
                {
                    Local3 = Zero
                    While ((Local3 < 0x1F) && ((TRDB & (One << Local3)) == Zero))
                    {
                        Local3++
                    }

                    Local4 = 0x1F
                    While ((Local4 > Zero) && ((TRDB & (One << Local4)) == Zero))
                    {
                        Local4--
                    }

                    UFXL (Local3)
                    UFXH (Local4)
                }
%s
                STOR = STOR + 1
%s
            }
        }
""" % (diff, "\n".join(ifs), save)

NOEXT = len(sys.argv) > 3 and sys.argv[3] == "noext"   # noext: no dynamic memory reads (they crash Windows: RAM mapped as MMIO)
if NOEXT:
    a = method.index("                If (TRDB != Zero)")
    b = method.index("                STOR = STOR + 1") if False else method.index("Q000 = Local2") - len("                ") - len("If (Local1 == 0x00)\n            {\n")
    method = method[:a] + method[b:]
block = "\n".join(hc) + "\n\n" + "\n".join(sn) + "\n\n" + pv + "\n" + ev + "\n" + ("" if NOEXT else extract(0) + extract(11)) + method + "\n"
marker = "        Method (_INI, 0, NotSerialized)  // _INI: Initialize\n"
assert marker in src
src = src.replace(marker, block + marker, 1)

n = 0
for tag in ("DBGL (0x10)  // trace _STA UFS0", "DBGL (0x12)  // trace _STA URS0/USB0"):
    assert tag in src, tag
    src = src.replace(tag, tag + "\n                UFSS ()", 1)
    n += 1
open(sys.argv[2], "w", encoding="utf-8").write(src)
print("ok; UFSS calls injected:", n)
