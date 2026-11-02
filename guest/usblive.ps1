# S:\rm9\usblive.ps1 - live USB device-mode experiment with rm9io (run as SYSTEM, function role already selected: RoleSwitchMode=2, USBFN config present).
# For every variant: restart the DRD node (function stack comes up), activate the bus (usbfn_activate.ps1), apply the tweak through MMIO, then log the DWC3/glue state every second for ~30 s
# (UFX gives up after its 30 s charge timer).  Watch the PC with refs\pc_usbwatch.ps1 and correlate by time.
function Add-Content {
    param([Parameter(Position = 0)]$Path, [Parameter(Position = 1)]$Value)
    $fs = New-Object IO.FileStream($Path, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
    $b = [Text.Encoding]::ASCII.GetBytes("$Value`r`n"); $fs.Write($b, 0, $b.Length); $fs.Dispose()
}
. S:\rm9\rm9io.ps1
. S:\rm9\qmp_seq.ps1
$log = 'C:\rm9\session\usblive.txt'
$U = [uint64]0xA600000; $Q = $U + 0xF8800; $P = [uint64]0x88E3000
function L($m) { Add-Content -Path $log -Value ('{0} {1}' -f (Get-Date -Format 'HH:mm:ss.ff'), $m) }
function R1([uint64]$a) { (Rm9Read $a 1)[0] }
$script:prevSnap = ''
function Snap($tag, [switch]$Force) {
    try {
        $dcfg = R1 ($U + 0xC700); $dctl = R1 ($U + 0xC704); $dsts = R1 ($U + 0xC70C)
        $spd = $dsts -band 7; $lnk = ($dsts -shr 18) -band 0xF
        $ev = '{0:X} {1:X} {2:X}' -f (R1 ($U + 0xC40C)), (R1 ($U + 0xC41C)), (R1 ($U + 0xC42C))
        $q10 = R1 ($Q + 0x10); $q30 = R1 ($Q + 0x30); $q58 = R1 ($Q + 0x58)
        $g2 = R1 ($U + 0xC200); $ltssm = R1 ($U + 0xC164)
        $key = ('DCFG={0:X8} DCTL={1:X8} spd={2} link={3:X} EVCNT={4} Q10={5:X8} Q30={6:X8} Q58={7:X8} G2={8:X8} LTSSM={9:X8}' -f $dcfg, $dctl, $spd, $lnk, $ev, $q10, $q30, $q58, $g2, $ltssm)
        if ($Force -or $key -ne $script:prevSnap) { L ("${tag}: " + $key + (' DSTS={0:X8}' -f $dsts)); $script:prevSnap = $key }
    } catch { L ("${tag}: read failed: " + $_.Exception.Message) }
}
function Override {
    Rm9Write ($Q + 0x10) 0x10100000 0x10100000
    Rm9Write ($Q + 0x30) 0x01000000 0x01000000
    Rm9Write ($Q + 0x08) 0x2 0x2
    L 'applied: QSCRATCH VBUS/session overrides + GENERAL_CFG'
}
function PhyInit {
    $init = @(@(0x94, 2), @(0x50, 2), @(0x54, 0x09090909), @(0x130, 4), @(0x98, 0), @(0xB8, 1), @(0x54, 0x09090949), @(0x5C, 0xC8C8C8C8), @(0x60, 0), @(0x60, 0), @(0x58, 0x02020202),
        @(0x68, 0x21212121), @(0x68, 0x21212121), @(0x6C, 0x50505050), @(0x70, 0), @(0x6C, 0x50505050), @(0x64, 0x07070717), @(0x7C, 0xC8C8C8C8), @(0x7C, 0xC8C8C8C8), @(0x7C, 0xC8C8C8C8),
        @(0x78, 0x18181818), @(0x78, 0x18181818), @(0x64, 0x1717171F), @(0x3C, 0x01010101), @(0x54, 0x4949494B), @(0x54, 0x4B4B4B4B), @(0x50, 0x02020200), @(0x64, 0x1F1F1F17))
    foreach ($w in $init) { Rm9Write ($P + $w[0]) ([uint32]$w[1]) }
    $conn = @(@(0x130, 0x04040400), @(0x138, 5), @(0x13C, 0xC0), @(0x130, 3), @(0x130, 0x03030300), @(0x13C, 0xC0C0C000), @(0x130, 3), @(0x130, 0x03030300))
    foreach ($w in $conn) { Rm9Write ($P + $w[0]) ([uint32]$w[1]) }
    L 'applied: eUSB2 PHY init table + notify_connect'
}
function RunToggle {
    Rm9Write ($U + 0xC704) 0 0x80000000
    Start-Sleep -Milliseconds 300
    Rm9Write ($U + 0xC704) 0x80000000 0x80000000
    L 'applied: DCTL.RunStop toggled'
}
function QmpInit {
    # replay of msm_ssphy_qmp_init as traced on Android (SS PHY of the USB3/DP combo PHY)
    foreach ($w in $QmpSeq) { Rm9Write ($QmpBase + $w[0]) ([uint32]$w[1]) }
    $st = 0
    for ($i = 0; $i -lt 50; $i++) { $st = R1 ($QmpBase + 0x1C14); if (($st -band 1) -eq 0) { break }; Start-Sleep -Milliseconds 10 }
    L ('applied: QMP SS PHY init ({0} writes), PCS_STATUS(+0x1C14)={1:X8} after {2} polls' -f $QmpSeq.Count, $st, $i)
}
function EudDetect {
    Rm9Write 0xC278000 1
    L ('applied: eud_detect_reg (0xC278000) = 1, readback {0:X8}' -f (R1 0xC278000))
}
function GccPrep {
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
function AndroidCore {
    # the dwc3 core configuration Android has while the PC link works (debugfs regdump)
    Rm9Write ($U + 0xC110) 0x00102000          # GCTL (clock gating enabled, PRTCAPDIR=device)
    Rm9Write ($U + 0xC12C) 0x0D014802          # GUCTL
    Rm9Write ($U + 0xC11C) 0x81001808          # GUCTL1
    Rm9Write ($U + 0xC2C0) 0x030E1002          # GUSB3PIPECTL
    Rm9Write ($U + 0xC200) 0x00102400          # GUSB2PHYCFG
    Rm9Write ($U + 0xC708) 0x00000E57          # DEVTEN
    L 'applied: Android dwc3 core registers (GCTL/GUCTL/GUCTL1/GUSB3PIPECTL/GUSB2PHYCFG/DEVTEN)'
}
function HsOnly {
    Rm9Write ($U + 0xC700) 0 7                      # DCFG.DEVSPD = HS (no SuperSpeed attempt)
    Rm9Write ($U + 0xC200) 0x102400                 # GUSB2PHYCFG as dwc3_otg_start_peripheral writes it (ENBLSLPM off)
    L 'applied: DCFG.DEVSPD=HS, GUSB2PHYCFG=0x102400'
}
function Variant([string]$name, [scriptblock]$apply) {
    L "=== variant $name"
    pnputil /restart-device 'ACPI\QCOM0C8B\0' | Out-Null
    Start-Sleep 8
    $act = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'S:\rm9\usbfn_activate.ps1', '-Seconds', '40' -PassThru -WindowStyle Hidden
    Start-Sleep 3
    Snap 'activated' -Force
    & $apply
    for ($i = 0; $i -lt 28; $i++) { Start-Sleep 1; Snap ('t+' + $i) }
    if (-not $act.HasExited) { Wait-Process -Id $act.Id -Timeout 30 -ErrorAction SilentlyContinue }
    Snap 'end'
}
L '##### usblive start'
L ('eud_detect_reg 0xC278000 = {0:X8}, eud_enable_reg 0x88E2000 = {1:X8}' -f (R1 0xC278000), (R1 0x88E2000))
Snap 'baseline'
function VariantPre([string]$name, [scriptblock]$pre, [scriptblock]$post) {
    L "=== variant $name (prep first, then restart the DRD node)"
    & $pre
    Variant "$name / after restart" $post
}
VariantPre 'N1 PHYs fully initialised, nothing else' { PhyFull } { }
VariantPre 'N2 PHYs fully initialised + overrides + android core regs + run toggle' { PhyFull } { Override; AndroidCore; RunToggle }
L '##### usblive done'
