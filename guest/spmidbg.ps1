$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$root\spmi.ps1"
if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne "Running") { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
$n = Spmi-Init
"mapped $n"
$list = $script:ApidOf.GetEnumerator() | Sort-Object Name | ForEach-Object { "{0:X3}->{1}" -f $_.Name, $_.Value }
($list -join " ")
# probe one mapped peripheral by hand and show the raw status
$first = ($script:ApidOf.GetEnumerator() | Sort-Object Name | Select-Object -First 1)
$ppid = $first.Name; $apid = $first.Value
$off = $SPMI_OBSRVR + 0x20 * $apid
"first ppid=0x{0:X3} apid={1} obsrvr=0x{2:X}" -f $ppid, $apid, $off
Rm9Write $off ([uint32]((1 -shl 27) -bor (4 -shl 4) -bor 1))
Start-Sleep -Milliseconds 5
"status after cmd: 0x{0:X8}  data: {1}" -f (Rm9Read ($off + 8) 1)[0], ((Rm9Read ($off + 0x18) 2 | ForEach-Object { "{0:X8}" -f $_ }) -join " ")
"obsrvr words +0..0x1c: " + ((Rm9Read $off 8 | ForEach-Object { "{0:X8}" -f $_ }) -join " ")
