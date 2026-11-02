# SYSTEM: find the scan-out stride of the physical framebuffer (0xE3940000) by locating desktop rows 1200/1201 (from shot.raw) inside it
. C:\rm9\link\rm9io.ps1
$W = 1116; $raw = [IO.File]::ReadAllBytes('C:\rm9\link\shot.raw'); $FB = [uint64]0xE3940000
$row = 1200; $col = 100; $len = 64
$p0 = $raw[((($row * $W) + $col) * 4)..((($row * $W) + $col + $len) * 4 - 1)]
$p1 = $raw[((((($row + 1) * $W)) + $col) * 4)..((((($row + 1) * $W) + $col + $len) * 4) - 1)]
$start = [uint64]($row * $W * 4 - 20000); $n = 40000 / 4
$words = New-Object System.Collections.Generic.List[uint32]
for ($o = 0; $o -lt $n; $o += 1000) { $c = [Math]::Min(1000, $n - $o); $words.AddRange([uint32[]](Rm9Read ($FB + $start + 4 * $o) $c)) }
$bytes = New-Object byte[] ($words.Count * 4); [Buffer]::BlockCopy($words.ToArray(), 0, $bytes, 0, $bytes.Length)
function Find($pat) { for ($i = 0; $i -le $bytes.Length - $pat.Length; $i += 4) { $ok = $true; for ($j = 0; $j -lt 32; $j += 1) { if ($bytes[$i + $j] -ne $pat[$j]) { $ok = $false; break } }; if ($ok) { return $i } }; return -1 }
$a = Find $p0; $b = Find $p1
"row0 pattern at FB offset: $a  (expected near 20000)"
"row1 pattern at FB offset: $b"
if ($a -ge 0 -and $b -ge 0) { "stride bytes = $($b - $a)  (pixels $((($b - $a) / 4)))" }
"shot.txt: " + (Get-Content C:\rm9\link\shot.txt)
