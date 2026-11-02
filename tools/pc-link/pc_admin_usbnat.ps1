# ELEVATED (PC): NAT for the phone's USB network (192.168.x.x/24, adapter rm9usb) through the PC's default-route interface (WinNAT, no ICS: ICS would disturb the Hyper-V/WSL default switch).
# Revert:  Remove-NetNat -Name rm9nat -Confirm:$false ; Set-NetIPInterface -InterfaceAlias rm9usb -Forwarding Disabled
param([switch]$Revert)
$log = '<RM9_WORKDIR>\winboot\usbnat.log'
function L($m) { Add-Content $log ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }
if ($Revert) { Remove-NetNat -Name rm9nat -Confirm:$false -ErrorAction SilentlyContinue; Set-NetIPInterface -InterfaceAlias rm9usb -Forwarding Disabled -ErrorAction SilentlyContinue; L 'reverted'; return }
$wan = (Get-NetRoute -DestinationPrefix 0.0.0.0/0 | Sort-Object RouteMetric | Select-Object -First 1).InterfaceAlias
L "wan interface: $wan"
Set-NetIPInterface -InterfaceAlias $wan -Forwarding Enabled
Set-NetIPInterface -InterfaceAlias rm9usb -Forwarding Enabled
New-NetFirewallRule -DisplayName 'rm9usb allow in' -Direction Inbound -InterfaceAlias rm9usb -Action Allow -ErrorAction SilentlyContinue | Out-Null
$n = New-NetNat -Name rm9nat -InternalIPInterfaceAddressPrefix 192.168.x.x/24 -ErrorAction Continue
L ("netnat: " + ($n | Out-String))
Get-NetNat | Out-String | ForEach-Object { L $_ }
