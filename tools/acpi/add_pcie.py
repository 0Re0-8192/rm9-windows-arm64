#!/usr/bin/env python3
"""add_pcie.py in.dsl out.dsl : add the PCIe0 host bridge (PCI0, PNP0A08, segment 0, root bus 1) and a PNP0C02 resource device for the ECAM window to the DSDT."""
import sys

src = open(sys.argv[1], encoding="utf-8").read()
assert "PNP0A08" not in src, "already patched"
asl = r'''
        // ---- PCIe0 host bridge: ECAM = iATU CFG window 0x60100000 (bus 1), memory window 0x60200000-0x61FFFFFF, MuChain (PCIE.TXT) brings the link up before Windows
        Device (RES0)
        {
            Name (_HID, EisaId ("PNP0C02"))  // motherboard resources
            Name (_UID, 0x50)
            Name (_CRS, ResourceTemplate ()
            {
                Memory32Fixed (ReadWrite, 0x60100000, 0x00100000)
            })
        }

        Device (PCI0)
        {
            Name (_HID, EisaId ("PNP0A08"))  // PCI Express Root Bridge
            Name (_CID, EisaId ("PNP0A03"))  // PCI Root Bridge
            Name (_UID, Zero)
            Name (_SEG, Zero)
            Name (_BBN, One)
            Name (_CCA, One)                 // DT: dma-coherent
            Method (_STA, 0, NotSerialized)
            {
                Return (0x0F)
            }

            Name (RBUF, ResourceTemplate ()
            {
                WordBusNumber (ResourceProducer, MinFixed, MaxFixed, PosDecode,
                    0x0000, 0x0001, 0x0001, 0x0000, 0x0001)
                DWordMemory (ResourceProducer, PosDecode, MinFixed, MaxFixed, NonCacheable, ReadWrite,
                    0x00000000, 0x60200000, 0x61FFFFFF, 0x00000000, 0x01E00000)
            })
            Method (_CRS, 0, NotSerialized)
            {
                Return (RBUF)
            }

            Method (_OSC, 4, NotSerialized)
            {
                CreateDWordField (Arg3, Zero, CDW1)
                If (Arg0 == ToUUID ("33db4d5b-1ff7-401c-9657-7441c03dd766"))
                {
                    If (Arg1 != One)
                    {
                        CDW1 |= 0x08
                    }
                    Else
                    {
                        // native control: only PME; the PCIe capability structure (ASPM / link control) stays with the firmware
                        CreateDWordField (Arg3, 8, CDW3)
                        If ((CDW3 & 0xFFFFFFFB) != Zero)
                        {
                            CDW3 &= 0x04
                            CDW1 |= 0x10
                        }
                    }
                }
                Else
                {
                    CDW1 |= 0x04
                }

                Return (Arg3)
            }

            Method (_DSM, 4, Serialized)
            {
                If (Arg0 == ToUUID ("e5c937d0-3553-4d7a-9117-ea4d19c3434d"))
                {
                    If (Arg2 == Zero)
                    {
                        Return (Buffer () { 0x21 })  // functions 0 and 5
                    }

                    If (Arg2 == 5)
                    {
                        Return (One)                 // ignore the boot configuration, let Windows assign the BARs
                    }
                }

                Return (Buffer () { Zero })
            }

            // legacy INTx of the RC: SPI 0x95..0x98 (int_a..int_d) = GSI 181..184, only device 0 exists
            Name (_PRT, Package ()
            {
                Package () { 0x0000FFFF, Zero, Zero, 181 },
                Package () { 0x0000FFFF, One, Zero, 182 },
                Package () { 0x0000FFFF, 2, Zero, 183 },
                Package () { 0x0000FFFF, 3, Zero, 184 }
            })
        }
'''
marker = "    Scope (\_TZ)"
i = src.index(marker)
j = src.rindex("    }", 0, i)
open(sys.argv[2], "w", encoding="utf-8").write(src[:j] + asl + "\n" + src[j:])
print("ok: PCI0 + RES0 inserted")
