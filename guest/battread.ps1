# battread.ps1 - read the battery snapshot MuChain left in RAM at 0xD7FF1000 (see MuChain.c BattSnapshot) through rm9io and print it.
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$root\rm9io.ps1"
if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne "Running") { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
$addr = [Convert]::ToUInt64("D7FF1000", 16)   # a hex literal that high is a negative Int32 in PowerShell - never type it as 0xD7FF1000
"reading 0x{0:X}" -f $addr
if ($addr -ne 3623817216) { "refusing: address is not the MuChain snapshot block"; exit 2 }   # 0xD7FF1000 - the only RAM address this script may read
$w = Rm9Read $addr 80
"magic=0x{0:X8} (BATT = 0x54544142)  count={1}" -f $w[0], $w[1]
if ($w[0] -ne 0x54544142) { "snapshot not valid"; exit 1 }
$names = @{ 0x300000 = "batt status"; 0x300001 = "health"; 0x300002 = "present"; 0x300004 = "capacity (0.01 %)"; 0x300007 = "voltage (uV)"; 0x300009 = "current (raw)"; 0x30000C = "temp (0.01 C)"
            0x30000D = "prop 0xD"; 0x30000E = "prop 0xE"; 0x30000F = "cycle count"; 0x300010 = "design capacity (uAh)"; 0x300011 = "full capacity (uAh)"; 0x300013 = "prop 0x13"; 0x30001B = "prop 0x1B"
            0x320000 = "usb online"; 0x320002 = "usb voltage (uV)"; 0x320004 = "usb current limit (uA)" }
for ($i = 0; $i -lt $w[1]; $i++) {
    $k = [int]$w[2 + 2 * $i]; $v = $w[3 + 2 * $i]
    $n = if ($names.ContainsKey($k)) { $names[$k] } else { "?" }
    "{0,-26} key=0x{1:X6} value={2} (0x{2:X})" -f $n, $k, $v
}
