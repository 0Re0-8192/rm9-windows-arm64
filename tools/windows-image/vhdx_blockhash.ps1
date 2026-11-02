# vhdx_blockhash.ps1 -Path <file> -Out <file> [-BlockMB 4]   (runs on the phone, Windows PowerShell 5.1)
# Writes 16 bytes (MD5) per BlockMB block of -Path to -Out, and C:\...\<Out>.done when finished.
param([string]$Path, [string]$Out, [int]$BlockMB = 4)
$bs = $BlockMB * 1MB
$md5 = [Security.Cryptography.MD5]::Create()
$fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
$o = [IO.File]::Create($Out)
$buf = New-Object byte[] $bs
$total = $fs.Length
$t0 = Get-Date
$n = 0
while ($true) {
  $r = 0
  while ($r -lt $bs) { $k = $fs.Read($buf, $r, $bs - $r); if ($k -le 0) { break }; $r += $k }
  if ($r -le 0) { break }
  $h = $md5.ComputeHash($buf, 0, $r)
  $o.Write($h, 0, 16)
  $n++
  if (($n % 200) -eq 0) { Set-Content -Path ($Out + '.progress') -Value ("{0} blocks {1:N0}s" -f $n, ((Get-Date) - $t0).TotalSeconds) }
}
$o.Close(); $fs.Close()
Set-Content -Path ($Out + '.done') -Value ("{0} blocks of {1} MB, size {2}, {3:N0}s" -f $n, $BlockMB, $total, ((Get-Date) - $t0).TotalSeconds)
