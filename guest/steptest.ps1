# steptest.ps1 - what does pci.sys / the qcwlan driver do at device start that stops the machine?  The driver is disabled (qcwlan Start=4).  We replay the likely steps one by one through rm9io,
# each logged (write-through) BEFORE it is done; the last line in C:\rm9\wifi_step.txt after a crash is the culprit.
$o = 'C:\rm9\wifi_step.txt'
$fs = New-Object IO.FileStream($o, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
function L($m) { $b = [Text.Encoding]::ASCII.GetBytes("$(Get-Date -Format 'HH:mm:ss.fff') $m`r`n"); $fs.Write($b, 0, $b.Length); $fs.Flush($true) }
function A([string]$h) { [Convert]::ToUInt64($h, 16) }
function Hx($a) { ($a | ForEach-Object { '{0:X8}' -f $_ }) -join ' ' }
function Rw32([string]$h, [uint32]$n = 1) { Rm9Read (A $h) $n }
. C:\rm9\link\rm9io.ps1
if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
Start-Sleep 70
L 'steptest start'
$EP = '60100000'
function Cfg([int]$off) { '{0:X8}' -f ((A $EP) + $off) }
for ($k = 0; $k -lt 4; $k++) { L (("EP ext+0x{0:X3}: " -f (0x100 + 0x40 * $k)) + (Hx (Rw32 (Cfg (0x100 + 0x40 * $k)) 16))) }
L ('EP[40..7C] ' + (Hx (Rw32 (Cfg 0x40) 16)))
L ('EP[80..BC] ' + (Hx (Rw32 (Cfg 0x80) 16)))
# BAR0 in place first (stage 1 of bartest showed this is safe)
L 'step 0: BAR0 = 0x60200000, memory space on'
Rm9Write (A (Cfg 0x10)) (A '60200004'); Rm9Write (A (Cfg 0x14)) 0
$cmd = (Rw32 (Cfg 4))[0]; Rm9Write (A (Cfg 4)) ($cmd -bor 2)
L ('MHI regs: ' + (Hx (Rw32 '60200000' 8)) + ' | status 0x48: ' + (Hx (Rw32 '60200048' 2)))
function Probe($tag) {
    L ("$tag EP[00..1C] " + (Hx (Rw32 (Cfg 0) 8)))
    L ("$tag link: EP " + (Hx (Rw32 (Cfg 0x80) 1)) + " RC " + (Hx (Rw32 '60000080' 1)) + " PARF1B0 " + (Hx (Rw32 '01C001B0' 1)))
    L ("$tag MHIVER " + (Hx (Rw32 '60200008' 1)) + " ERDBOFF " + (Hx (Rw32 '60200020' 1)))
}
L 'step 1: bus master enable'
$cmd = (Rw32 (Cfg 4))[0]; Rm9Write (A (Cfg 4)) ($cmd -bor 4)
Probe 'after1'
L 'step 2: Device Control 2: LTR mechanism enable (EP 0x98 bit 10)'
$v = (Rw32 (Cfg 0x98))[0]; Rm9Write (A (Cfg 0x98)) ($v -bor 0x400)
Probe 'after2'
L 'step 3: Link Control: ASPM L1 enable (EP 0x80 bit 1)'
$v = (Rw32 (Cfg 0x80))[0]; Rm9Write (A (Cfg 0x80)) ($v -bor 2)
Probe 'after3'
Start-Sleep 2
Probe 'after3+2s'
L 'step 4: MSI: address 0x17140040, data 0, enable'
Rm9Write (A (Cfg 0x54)) (A '17140040'); Rm9Write (A (Cfg 0x58)) 0
$v = (Rw32 (Cfg 0x50))[0]; Rm9Write (A (Cfg 0x50)) ($v -bor 0x10000)
Probe 'after4'
L 'step 5: MHICTRL reset (0x60200038 = 2)'
Rm9Write (A '60200038') 2
for ($i = 0; $i -lt 10; $i++) { Start-Sleep -Milliseconds 300; L ("poll$i MHICTRL " + (Hx (Rw32 '60200038' 1)) + " MHISTATUS " + (Hx (Rw32 '60200048' 1)) + " MHIVER " + (Hx (Rw32 '60200008' 1))) }
Probe 'after5'
L 'all steps passed'
# ITS / GIC: can Windows read them at all?  (logged before each read)
foreach ($r in @(@('GICD_CTLR', '17100000'), @('GICD_TYPER', '17100004'), @('GICR0_TYPER', '17180008'), @('GICR0_WAKER', '17180014'), @('GICR0_PROPBASER', '17180070'), @('GICR0_PENDBASER', '17180078'), @('GITS_CTLR', '17140000'), @('GITS_IIDR', '17140004'), @('GITS_TYPER', '17140008'), @('GITS_CBASER', '17140080'), @('GITS_CWRITER', '17140088'), @('GITS_CREADR', '17140090'), @('GITS_BASER0', '17140100'), @('GITS_BASER1', '17140108'))) {
    L ("reading " + $r[0] + " @" + $r[1])
    L ($r[0] + " = " + (Hx (Rw32 $r[1] 1)))
}
L 'ITS reads passed'
