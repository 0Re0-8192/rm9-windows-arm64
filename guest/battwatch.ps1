# battwatch.ps1 - log what Windows sees of the battery every 30 s (C:\rm9\battwatch.txt): proves that the ACPI Notify -> cmbatt -> WMI path follows the live RAM block.
param([int]$Seconds = 540, [int]$Period = 30)
$out = "C:\rm9\battwatch.txt"
# battery temperature (ADSP battmgr key 0x30000C, 0.01 C) from the RAM block battlive.ps1 keeps up to date at 0xD7FF1000 (read-only)
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$root\rm9io.ps1"
$BATT = [Convert]::ToUInt64("D7FF1000", 16)
function BattTemp() {
    try {
        $w = Rm9Read $BATT 40
        if ($w[0] -ne 0x54544142) { return "n/a" }
        for ($i = 0; $i -lt $w[1] -and $i -lt 18; $i++) { if ($w[2 + 2 * $i] -eq 0x30000C) { return ("{0:F2}C" -f ([int]$w[3 + 2 * $i] / 100.0)) } }
    } catch { }
    return "n/a"
}
$t0 = Get-Date
while (((Get-Date) - $t0).TotalSeconds -lt $Seconds) {
    try {
        $b = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction Stop | Select-Object -First 1
        $w = Get-CimInstance Win32_Battery -ErrorAction Stop | Select-Object -First 1
        "{0} V={1} mV rem={2} chg={3} dis={4} ac={5} rate={6}/{7} est={8}% status={9} bT={10}" -f (Get-Date -Format HH:mm:ss), $b.Voltage, $b.RemainingCapacity, $b.Charging, $b.Discharging, $b.PowerOnline, $b.ChargeRate, $b.DischargeRate, $w.EstimatedChargeRemaining, $w.BatteryStatus, (BattTemp) | Out-File -Append -Encoding ascii $out
    } catch { "{0} ERR {1}" -f (Get-Date -Format HH:mm:ss), $_ | Out-File -Append -Encoding ascii $out }
    Start-Sleep -Seconds $Period
}
