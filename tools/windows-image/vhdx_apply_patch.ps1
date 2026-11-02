# vhdx_apply_patch.ps1 -Target <file> -Patch <file>   (runs on the phone, Windows PowerShell 5.1)
# Patch format: u64 final size, u32 block count, then per block: u64 offset, u32 length, <length bytes>.
# Applies the blocks in place to Target (which must be closed) and writes <Patch>.applied when finished.
param([string]$Target, [string]$Patch)
$pf = [IO.File]::OpenRead($Patch)
$br = New-Object IO.BinaryReader($pf)
$size = $br.ReadUInt64()
$cnt = $br.ReadUInt32()
$tf = [IO.File]::Open($Target, 'Open', 'ReadWrite', 'None')
if ($tf.Length -ne [int64]$size) { $tf.SetLength([int64]$size) }
$t0 = Get-Date
for ($i = 0; $i -lt $cnt; $i++) {
  $off = $br.ReadUInt64()
  $len = $br.ReadUInt32()
  $data = $br.ReadBytes($len)
  if ($data.Length -ne $len) { throw "short read at block $i" }
  $tf.Seek([int64]$off, 'Begin') | Out-Null
  $tf.Write($data, 0, $len)
  if (($i % 50) -eq 0) { Set-Content -Path ($Patch + '.progress') -Value ("{0}/{1} {2:N0}s" -f $i, $cnt, ((Get-Date) - $t0).TotalSeconds) }
}
$tf.Flush($true)
$tf.Close(); $pf.Close()
Set-Content -Path ($Patch + '.applied') -Value ("{0} blocks, {1:N0}s" -f $cnt, ((Get-Date) - $t0).TotalSeconds)
