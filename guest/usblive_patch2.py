p = '<RM9_WORKDIR>/refs/winpe/usblive.ps1'
s = open(p, encoding='utf-8', newline='').read()

# 1. GccPrep: the clock / reset steps found in the Android boot-time trace (winboot/usbtrace3), then HS PHY init, then QMP init (with the BCR pulses in front, as Android does)
a = 'function AndroidCore {'
assert a in s
prep = r'''function GccPrep {
    # what Android does right before it touches the PHYs (GDSCs, TCSR USB clkrefs, PHY aux/pipe clocks), then the eUSB2 PHY BCR pulse (GCC+0x12000) and the USB3 / DP PHY BCR pulses (GCC+0x50000 / 0x50008)
    $G = [uint64]0x100000; $T = [uint64]0x1FF1000
    Rm9Write ($G + 0x39004) 0 1            # usb30_prim gdsc on (SW_COLLAPSE = 0)
    Rm9Write ($G + 0x50018) 0 1            # usb3_phy gdsc on
    Rm9Write ($T + 0x118) 1                # tcsr usb clkref enables
    Rm9Write ($T + 0x108) 1
    Rm9Write ($G + 0x39064) 1 1; Rm9Write ($G + 0x39060) 1 1; Rm9Write ($G + 0x39068) 1 1
    Start-Sleep -Milliseconds 2
    L ('applied: GCC/TCSR clocks (gdsc usb30={0:X8} usb3phy={1:X8} clkref108={2:X8} clkref118={3:X8})' -f (R1 ($G + 0x39004)), (R1 ($G + 0x50018)), (R1 ($T + 0x108)), (R1 ($T + 0x118)))
}
function BcrHs { $G = [uint64]0x100000; Rm9Write ($G + 0x12000) 1; Start-Sleep -Milliseconds 1; Rm9Write ($G + 0x12000) 0; L 'applied: eUSB2 PHY BCR pulse (GCC+0x12000)' }
function BcrSs { $G = [uint64]0x100000; Rm9Write ($G + 0x50008) 1; Rm9Write ($G + 0x50000) 1; Start-Sleep -Milliseconds 1; Rm9Write ($G + 0x50000) 0; Rm9Write ($G + 0x50008) 0; L 'applied: USB3 / DP PHY BCR pulses (GCC+0x50000 / 0x50008)' }
function PhyFull { GccPrep; Rm9Write 0xC278000 1; BcrHs; PhyInit; Start-Sleep -Milliseconds 1; BcrSs; QmpInit }
'''
s = s.replace(a, prep + a, 1)

# 2. variants: prepare the PHYs first (function role), then restart the DRD so that UFX starts on healthy PHYs; and a second variant with the overrides / core regs / run toggle on top
i = s.index("Variant 'A baseline (no tweak)' { }")
j = s.index("L '##### usblive done'")
new = r'''function VariantPre([string]$name, [scriptblock]$pre, [scriptblock]$post) {
    L "=== variant $name (prep first, then restart the DRD node)"
    & $pre
    Variant "$name / after restart" $post
}
VariantPre 'N1 PHYs fully initialised, nothing else' { PhyFull } { }
VariantPre 'N2 PHYs fully initialised + overrides + android core regs + run toggle' { PhyFull } { Override; AndroidCore; RunToggle }
'''
s = s[:i] + new + s[j:]
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
