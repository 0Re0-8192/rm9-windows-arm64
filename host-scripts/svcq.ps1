reg query HKLM\SYSTEM\CurrentControlSet\Services\qcwlan /s
'---- ep'
reg query 'HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}\0002' 2>&1 | Select-Object -First 30
'---- inf AddService'
Select-String -Path 'C:\Windows\System32\DriverStore\FileRepository\qcwlanhmt8380.inf_arm64_*\qcwlanhmt8380.inf' -Pattern 'AddService|ServiceType|StartType|ErrorControl|ServiceBinary|LoadOrderGroup|DisplayName' | ForEach-Object { $_.Line.Trim() } | Select-Object -First 20
