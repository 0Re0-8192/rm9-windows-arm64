#!/usr/bin/env python3
"""Add an ACPI device that owns the GIC SPIs 800..811 (the Wi-Fi chip's MSIs redirected to the MBI frame, NEXT.md 0az) so the HAL translates them to
system vectors and a driver can connect them.   add_irq.py in.dsl out.dsl
Windows ARM64 only maps an interrupt to a vector for devices whose resources come from ACPI _CRS (a ROOT-enumerated INF's IRQConfig stays untranslated, NEXT.md 0ba).
GSIV = GIC INTID (SPI n = INTID n+32; the _PRT in PCI0 uses the same convention)."""
import sys

src = open(sys.argv[1], encoding="utf-8", newline="").read()
nl = "\r\n" if "\r\n" in src else "\n"
assert "RM9I0001" not in src, "already patched"
first, count = 800, 12
asl = """
        // ---- owner of the MBI SPIs 800..811 for rm9irq.sys (the WCN7850's MSI vectors 0..11 write INTID 800 + vector to the MBI frame 0x17110040)
        Device (RIRQ)
        {
            Name (_HID, "RM9I0001")
            Name (_UID, Zero)
            Method (_STA, 0, NotSerialized)
            {
                Return (0x0F)
            }

            Name (_CRS, ResourceTemplate ()
            {
                Interrupt (ResourceConsumer, Edge, ActiveHigh, Exclusive, ,, )
                {
%s
                }
            })
        }
""" % ",\n".join("                    %d" % (first + i) for i in range(count))
asl = asl.replace("\n", nl)
marker = "    }" + nl + nl + r"    Scope (\_TZ)"
i = src.index(marker)
out = src[:i] + asl.lstrip(nl) + nl + src[i:]
open(sys.argv[2], "w", encoding="utf-8", newline="").write(out)
print("ok: RIRQ (SPI %d..%d) inserted before Scope (_TZ)" % (first, first + count - 1))
