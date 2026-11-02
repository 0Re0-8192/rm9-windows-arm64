# SYSTEM: dump the Apps SMMU stream-match / S2CR tables and context-bank state (rm9io) -> C:\rm9\link\smmu.txt   (is the touch controller's stream 0xA3 mapped?)
. C:\rm9\touch\rm9io.ps1
Rm9Open
$o = 'C:\rm9\link\smmu.txt'
"sCR0=$('{0:X8}' -f (Rm9Read 0x15000000 1)[0]) IDR0=$('{0:X8}' -f (Rm9Read 0x15000020 1)[0]) IDR1=$('{0:X8}' -f (Rm9Read 0x15000024 1)[0]) GCC_QUP_EN=$('{0:X8}' -f (Rm9Read 0x152008 1)[0])" | Out-File $o -Encoding ascii
$num = (Rm9Read 0x15000020 1)[0] -band 0xFF
"NUMSMRG=$num" | Out-File $o -Append -Encoding ascii
$sm = Rm9Read 0x15000800 107
$s2 = Rm9Read 0x15000C00 107
$valid = 0
for ($i = 0; $i -lt 107; $i++) {
    $v = (($sm[$i] -band 0x80000000) -ne 0)
    if ($v) { $valid++ }
    if ($v -or ((($s2[$i] -shr 16) -band 3) -ne 2)) { "i=$i smr=$('{0:X8}' -f $sm[$i]) s2cr=$('{0:X8}' -f $s2[$i])" | Out-File $o -Append -Encoding ascii }
}
"valid smr entries: $valid" | Out-File $o -Append -Encoding ascii
$cb = Rm9Read 0x15001000 16
"CBAR[0..15]: " + (($cb | ForEach-Object { '{0:X8}' -f $_ }) -join ' ') | Out-File $o -Append -Encoding ascii
