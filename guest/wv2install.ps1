# wv2install.ps1 - unpack the Edge WebView2 runtime (UUP FOD component, 141.0.3537.71) and register it the way the Evergreen runtime is discovered
$ver = '141.0.3537.71'
$dst = "C:\Program Files (x86)\Microsoft\EdgeWebView\Application\$ver"
New-Item -ItemType Directory -Force -Path $dst | Out-Null
& tar.exe -xf C:\rm9\link\wv2.tar -C $dst
"files: " + (Get-ChildItem $dst -Recurse -File | Measure-Object).Count
Test-Path "$dst\msedgewebview2.exe"
foreach ($base in 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}','HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}') {
  New-Item -Path $base -Force | Out-Null
  New-ItemProperty -Path $base -Name pv -Value $ver -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $base -Name name -Value 'Microsoft Edge WebView2 Runtime' -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $base -Name location -Value "C:\Program Files (x86)\Microsoft\EdgeWebView\Application" -PropertyType String -Force | Out-Null
}
'registered'
