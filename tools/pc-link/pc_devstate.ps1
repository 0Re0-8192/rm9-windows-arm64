# PC side: while the phone's function device (VID_1209) is present, log its PnP state every second: problem code, status, interfaces, registry GUIDs.
param([int]$Seconds = 1300, [string]$Out = '<RM9_WORKDIR>\winboot\pc_devstate.txt')
$end = (Get-Date).AddSeconds($Seconds); $last = ''
Add-Content $Out "--- start $(Get-Date -Format 'HH:mm:ss')"
while ((Get-Date) -lt $end) {
    $devs = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'USB\VID_1209&PID_000*' }
    $s = ''
    foreach ($d in $devs) {
        $p = Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode','DEVPKEY_Device_ProblemStatus' -ErrorAction SilentlyContinue
        $g = ''
        try { $g = (Get-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Enum\' + $d.InstanceId + '\Device Parameters') -ErrorAction Stop).DeviceInterfaceGUIDs -join ',' } catch {}
        $s += ('{0} status={1} class={2} problem={3} pstatus={4} guids={5}' -f $d.InstanceId, $d.Status, $d.Class, ($p | Where-Object KeyName -like '*ProblemCode').Data, ('0x{0:X}' -f [int](($p | Where-Object KeyName -like '*ProblemStatus').Data)), $g) + "`r`n"
    }
    if ($s -ne $last) { Add-Content $Out ("{0}`r`n{1}" -f (Get-Date -Format 'HH:mm:ss'), $s); $last = $s }
    Start-Sleep 1
}
