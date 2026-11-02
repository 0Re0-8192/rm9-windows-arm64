@echo off
rem starts the block-hash job detached (so rm9link exec returns at once)
del C:\w26100_remote.md5 C:\w26100_remote.md5.done C:\w26100_remote.md5.progress 2>nul
start "" /min powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\vhdx_blockhash.ps1 -Path C:\w26100.vhdx -Out C:\w26100_remote.md5 -BlockMB 4
echo started
dir C:\w26100.vhdx
