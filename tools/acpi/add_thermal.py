#!/usr/bin/env python3
"""Add ACPI ThermalZones backed by the SoC TSENS blocks (read via SystemMemory, no kernel driver needed).

  add_thermal.py in.dsl out.dsl

TSENS v2 layout (verified on the phone from Mu: values 31-33 C, same as Android): status of sensor n at block+0xA0+4n,
bits[11:0] signed deci-degC, bit 21 valid.  Sensor -> zone assignment follows the device tree (refs/dts_thermal_map.py):
  CPU     : tsens0 1..14 (cpuss, cpu-2-*, cpu-1-0/1-*), tsens1 1..5 (cpu-1-2-*, cpu-0-*)
  GPU     : tsens2 1..8 (gpuss-*)
  PLATFORM: aoss, nsp, video, ddr, camera, modem subsystems
Each zone returns the hottest valid sensor in deci-Kelvin and has a critical trip (_CRT) so Windows shuts down before damage."""
import sys

src = open(sys.argv[1], encoding="utf-8").read()
assert "TSN0" not in src

BASES = {0: 0x0C228000, 1: 0x0C229000, 2: 0x0C22A000}
NSENS = {0: 15, 1: 16, 2: 13}
ZONES = {
    "TZCP": ("CPU", 3832, [(0, i) for i in range(1, 15)] + [(1, i) for i in range(1, 6)]),
    "TZGP": ("GPU", 3832, [(2, i) for i in range(1, 9)]),
    "TZPL": ("PLATFORM", 3732, [(0, 0), (1, 0)] + [(1, i) for i in range(6, 16)] + [(2, 0)] + [(2, i) for i in range(9, 13)]),
}

regs = []
for c, base in BASES.items():
    regs.append("        OperationRegion (TSN%d, SystemMemory, 0x%08X, 0x200)" % (c, base))
    regs.append("        Field (TSN%d, DWordAcc, NoLock, Preserve)" % c)
    regs.append("        {")
    regs.append("            Offset (0xA0),")
    for n in range(NSENS[c]):
        regs.append("            T%dS%X,   32%s" % (c, n, "," if n < NSENS[c] - 1 else ""))
    regs.append("        }")
regs.append("""
        Method (TCNV, 1, NotSerialized)   // raw TSENS status -> deci-Kelvin (0 = invalid sample)
        {
            If ((Arg0 & 0x00200000) == Zero)
            {
                Return (Zero)
            }

            Local0 = Arg0 & 0x0FFF
            If ((Local0 & 0x0800) != Zero)
            {
                Return (2732)             // below 0 C: report 0 C
            }

            Return (Local0 + 2732)        // deci-C + 273.2 K
        }
""")

zones = ["    Scope (\\_TZ)", "    {"]
for name, (label, crt, sens) in ZONES.items():
    body = ["        ThermalZone (%s)   // %s" % (name, label), "        {", "            Name (_TZP, 100)    // poll every 10 s", "            Name (_CRT, %d)" % crt, "            Method (_TMP, 0, NotSerialized)", "            {", "                Local1 = Zero"]
    for c, n in sens:
        body.append("                Local0 = \\_SB.TCNV (\\_SB.T%dS%X)" % (c, n))
        body.append("                If (Local0 > Local1)")
        body.append("                {")
        body.append("                    Local1 = Local0")
        body.append("                }")
        body.append("")
    body += ["                If (Local1 == Zero)", "                {", "                    Local1 = 2982       // no valid sample: 25 C", "                }", "", "                Return (Local1)", "            }", "        }", ""]
    zones += body
zones.append("    }")

marker = "        Method (_INI, 0, NotSerialized)  // _INI: Initialize\n"
assert marker in src
src = src.replace(marker, "\n".join(regs) + "\n\n" + marker, 1)
idx = src.rstrip().rfind("}")
assert idx > 0
src = src[:idx].rstrip() + "\n\n" + "\n".join(zones) + "\n}\n"
open(sys.argv[2], "w", encoding="utf-8").write(src)
print("zones:", ", ".join("%s(%d sensors)" % (k, len(v[2])) for k, v in ZONES.items()))
