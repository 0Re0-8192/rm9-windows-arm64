# prevcrumb.ps1 - save the breadcrumbs dbgcap.sys found in DRAM from the PREVIOUS boot (written even if that boot hung) to S:\rm9\prevcrumb.txt
. S:\rm9\dbgcap.ps1
$o = 'S:\rm9\prevcrumb_' + (Get-Date -Format 'MMdd_HHmmss') + '.txt'
try {
    $ms = New-Object System.IO.MemoryStream
    $off = 0; $total = -1
    while ($true) {
        $r = [DbgCap]::Prev([uint32]$off)
        if (-not $r) { break }
        $total = [BitConverter]::ToUInt32($r, 0)
        if ($r.Length -le 4) { break }
        $ms.Write($r, 4, $r.Length - 4); $off += $r.Length - 4
        if ($off -ge $total) { break }
    }
    $txt = [Text.Encoding]::ASCII.GetString($ms.ToArray())
    $hdr = "=== prevcrumb saved " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " total=" + $total + " got=" + $ms.Length + "`r`n"
    [IO.File]::WriteAllText($o, $hdr + $txt, [Text.Encoding]::ASCII)
} catch { ("prevcrumb failed: " + $_) | Out-File -Append -Encoding ascii $o }
