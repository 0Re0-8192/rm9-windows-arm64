@echo off
rem applies C:\patch.bin to C:\w26100.vhdx, detached
del C:\patch.bin.applied C:\patch.bin.progress 2>nul
dir C:\patch.bin
start "" /min powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\vhdx_apply_patch.ps1 -Target C:\w26100.vhdx -Patch C:\patch.bin
echo started
