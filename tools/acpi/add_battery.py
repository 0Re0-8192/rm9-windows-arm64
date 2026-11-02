#!/usr/bin/env python3
"""Add an ACPI Control Method Battery (PNP0C0A) and an AC adapter (ACPI0003) to the DSDT.   add_battery.py in.dsl out.dsl

Data source: a fixed-slot block in RAM at physical 0xD7FF1000 (the MuChain.c BattSnapshot block; later a Windows-side service keeps it
up to date).  Layout: u32 magic 'BATT' (0x54544142), u32 slot count, then slot i = {u32 key, u32 value} at 8 + 8*i, value 0xFFFFFFFF = unknown.
Slots (qti_battery_charger glink properties, see NEXT.md 0h):
   0 status (0 unknown, 1 charging, 2 discharging, 3 not charging, 4 full)   1 health   2 present   3 capacity (0.01 %)   4 voltage (uV)
   5 current (signed 32 bit uA, NEGATIVE = charging)   6 temp (0.01 C)   7 ?   8 ?   9 cycle count   10 design capacity (uAh)   11 full capacity (uAh)
   12 ?   13 ?   14 usb online   15 usb voltage (uV)   16 usb current limit (uA)
The battery reports in mAh / mA (power unit 1)."""
import sys

src = open(sys.argv[1], encoding="utf-8").read()
assert "BTM0" not in src, "already patched"

fields = []
for i in range(17):
    fields.append("            BK%02d,   32," % i)
    fields.append("            BV%02d,   32%s" % (i, "," if i < 16 else ""))

asl = """
        // ---- battery / AC adapter backed by the RAM block written by MuChain (and later by a Windows service)
        OperationRegion (BTM0, SystemMemory, 0xD7FF1000, 0x100)
        Field (BTM0, DWordAcc, NoLock, Preserve)
        {
            BMAG,   32,
            BCNT,   32,
%s
        }

        Method (BOK, 0, NotSerialized)         // 1 when MuChain's snapshot is there
        {
            Return (BMAG == 0x54544142)
        }

        Method (BVAL, 1, NotSerialized)        // value of a slot, 0 when unknown (Arg0 = slot index, only the ones we use)
        {
            Local0 = 0xFFFFFFFF
            If (Arg0 == 0)  { Local0 = BV00 }
            If (Arg0 == 2)  { Local0 = BV02 }
            If (Arg0 == 3)  { Local0 = BV03 }
            If (Arg0 == 4)  { Local0 = BV04 }
            If (Arg0 == 5)  { Local0 = BV05 }
            If (Arg0 == 10) { Local0 = BV10 }
            If (Arg0 == 11) { Local0 = BV11 }
            If (Arg0 == 14) { Local0 = BV14 }
            If (Local0 == 0xFFFFFFFF)
            {
                Return (Zero)
            }

            Return (Local0)
        }

        // ---- change detection, called from the thermal zones' _TMP (Windows polls them every 10 s): tell cmbatt when the battery data changed
        Name (BLST, 0xFFFFFFFF)        // last remaining-capacity slot (0.01 %%)
        Name (BLSS, 0xFFFFFFFF)        // last status slot
        Name (BLSV, 0xFFFFFFFF)        // last voltage, in 50 mV steps
        Name (BLSA, 0xFFFFFFFF)        // last AC online
        Method (BCHK, 0, NotSerialized)
        {
            If (!BOK ())
            {
                Return (Zero)
            }

            Local0 = BVAL (3) / 100        // percent
            Local1 = BVAL (0)              // status
            Local2 = BVAL (4) / 50000      // voltage / 50 mV
            Local3 = BVAL (14) & One       // AC online
            If (Local3 != BLSA)
            {
                BLSA = Local3
                Notify (ADP1, 0x80)        // AC adapter status changed
                Notify (BAT0, 0x81)        // battery information (_BIF/_BIX) may have changed
                Notify (BAT0, 0x80)
            }

            If ((Local0 != BLST) || (Local1 != BLSS) || (Local2 != BLSV))
            {
                BLST = Local0
                BLSS = Local1
                BLSV = Local2
                Notify (BAT0, 0x80)        // battery status (_BST) changed
            }
        }

        Device (ADP1)
        {
            Name (_HID, "ACPI0003")
            Method (_PSR, 0, NotSerialized)
            {
                If (BOK ())
                {
                    Return (BVAL (14) & One)
                }

                Return (One)                   // no snapshot: assume the cable is there
            }

            Method (_STA, 0, NotSerialized)
            {
                Return (0x0F)
            }

            Name (_PCL, Package (One) { \\_SB })
        }

        Device (BAT0)
        {
            Name (_HID, EisaId ("PNP0C0A"))
            Name (_UID, One)
            Name (_PCL, Package (One) { \\_SB })

            Method (_STA, 0, NotSerialized)
            {
                If (BOK ())
                {
                    If (BVAL (2) != Zero)
                    {
                        Return (0x1F)          // present, enabled, shown, functioning, battery present
                    }
                }

                Return (0x0F)                  // device there, battery absent
            }

            Name (PBIF, Package (13)
            {
                One,                       // power unit: mA / mAh
                6500,                      // design capacity
                5266,                      // last full charge
                One,                       // rechargeable
                7700,                      // design voltage, mV (2S Li-ion)
                527,                       // warning capacity (10 %%)
                263,                       // low capacity (5 %%)
                One,
                One,
                "RM9",
                "0001",
                "LION",
                "ZTE"
            })
            Method (_BIF, 0, NotSerialized)
            {
                Local0 = BVAL (10) / 1000      // design capacity, mAh
                Local1 = BVAL (11) / 1000      // last full charge capacity, mAh
                If (Local0 == Zero) { Local0 = 6500 }
                If (Local1 == Zero) { Local1 = Local0 }
                PBIF [1] = Local0
                PBIF [2] = Local1
                PBIF [5] = Local1 / 10
                PBIF [6] = Local1 / 20
                Return (PBIF)
            }

            Name (PBIX, Package (20)
            {
                Zero,                      // revision
                One,                       // power unit: mA / mAh
                6500,                      // design capacity
                5266,                      // last full charge
                One,                       // rechargeable
                7700,                      // design voltage, mV
                527,                       // warning
                263,                       // low
                Zero,                      // cycle count
                99000,                     // measurement accuracy 99.000 %%
                0xFFFFFFFF,                // max sampling time (unknown)
                0xFFFFFFFF,                // min sampling time
                0xFFFFFFFF,                // max averaging interval
                0xFFFFFFFF,                // min averaging interval
                One,                       // granularity 1
                One,                       // granularity 2
                "RM9",
                "0001",
                "LION",
                "ZTE"
            })
            Method (_BIX, 0, NotSerialized)
            {
                Local0 = BVAL (10) / 1000
                Local1 = BVAL (11) / 1000
                If (Local0 == Zero) { Local0 = 6500 }
                If (Local1 == Zero) { Local1 = Local0 }
                PBIX [2] = Local0
                PBIX [3] = Local1
                PBIX [6] = Local1 / 10
                PBIX [7] = Local1 / 20
                PBIX [8] = BVAL (9)        // cycle count (slot 9), 0 when unknown
                Return (PBIX)
            }

            Name (PBST, Package (4) { Zero, Zero, Zero, Zero })
            Method (_BST, 0, NotSerialized)
            {
                Local0 = Zero                  // state bitmask: 1 discharging, 2 charging, 4 critical
                Local1 = Zero                  // present rate, mA
                Local2 = BVAL (11) / 1000      // full capacity, mAh
                If (Local2 == Zero) { Local2 = 6500 }
                Local3 = (BVAL (3) * Local2) / 10000      // remaining capacity, mAh
                Local4 = BVAL (4) / 1000                  // voltage, mV
                If (BOK ())
                {
                    Local5 = BVAL (5)                     // signed 32 bit uA, negative = charging
                    Local6 = BVAL (0)
                    If (Local5 & 0x80000000)
                    {
                        Local5 = (0x100000000 - Local5)    // magnitude
                        Local7 = One                      // 1 = was negative
                    }
                    Else
                    {
                        Local7 = Zero
                    }

                    Local1 = Local5 / 1000
                    If (Local6 == One)
                    {
                        Local0 = 2                        // charging
                    }
                    ElseIf (Local6 == 2)
                    {
                        Local0 = One                      // discharging
                    }
                    ElseIf (Local6 == Zero)
                    {
                        If (Local7 != Zero)
                        {
                            Local0 = 2                    // status unknown: negative current = charging
                        }
                        ElseIf (Local1 > 20)
                        {
                            Local0 = One
                        }
                    }

                    If (Local0 == One)
                    {
                        If (BVAL (3) < 500)
                        {
                            Local0 = 5                    // discharging and below 5 %%: critical
                        }
                    }
                }

                PBST [0] = Local0
                PBST [1] = Local1
                PBST [2] = Local3
                PBST [3] = Local4
                Return (PBST)
            }
        }
""" % "\n".join(fields)

# insert at the end of Scope (_SB): the line "    }" right before "    Scope (\_TZ)"
marker = "    Scope (\\_TZ)"
i = src.index(marker)
j = src.rindex("    }", 0, i)
out = src[:j] + asl + "\n" + src[j:]
open(sys.argv[2], "w", encoding="utf-8").write(out)
print("ok: battery + AC adapter inserted before Scope (_TZ)")
