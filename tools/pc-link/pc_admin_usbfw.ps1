# ELEVATED (PC): firewall for the phone's USB network
Get-NetFirewallRule -DisplayName 'rm9usb*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName 'rm9usb icmp in' -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Allow -Profile Any | Out-Null
New-NetFirewallRule -DisplayName 'rm9usb allow in' -Direction Inbound -RemoteAddress 192.168.x.x/24 -Action Allow -Profile Any | Out-Null
New-NetFirewallRule -DisplayName 'rm9usb allow out' -Direction Outbound -RemoteAddress 192.168.x.x/24 -Action Allow -Profile Any | Out-Null
Set-NetConnectionProfile -InterfaceAlias rm9usb -NetworkCategory Private -ErrorAction SilentlyContinue
Add-Content <RM9_WORKDIR>\winboot\usbnat.log ("{0} firewall rules set" -f (Get-Date -Format 'HH:mm:ss'))
