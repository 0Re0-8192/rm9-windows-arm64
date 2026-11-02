@echo off
rem Build dbgcap.sys for ARM64 with the VS 2022 cross compiler + WDK 10.0.19041 kernel headers/libs, then test-sign it.
rem usage: build.bat            (run from drv\dbgcap)
setlocal
set WDK=C:\Program Files (x86)\Windows Kits\10
set WV=10.0.19041.0
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsamd64_arm64.bat" >nul
if errorlevel 1 (echo vcvars failed & exit /b 1)
if not exist out mkdir out
cl /nologo /kernel /GS- /W3 /O2 /Zi /c /D_ARM64_ /DARM64 /D_WIN64 /DNTDDI_VERSION=0x0A000007 /D_WIN32_WINNT=0x0A00 /DWINVER=0x0A00 /DPOOL_NX_OPTIN=1 ^
   /I"%WDK%\Include\%WV%\km" /I"%WDK%\Include\%WV%\shared" /I"%WDK%\Include\%WV%\um" /Fo:out\dbgcap.obj dbgcap.c
if errorlevel 1 (echo compile failed & exit /b 1)
armasm64 -nologo smc.asm -o out\smc.obj
if errorlevel 1 (echo armasm failed & exit /b 1)
link /nologo /DRIVER /SUBSYSTEM:NATIVE /ENTRY:DriverEntry /NODEFAULTLIB /MACHINE:ARM64 /OUT:out\dbgcap.sys /PDB:out\dbgcap.pdb out\dbgcap.obj out\smc.obj ^
   /LIBPATH:"%WDK%\Lib\%WV%\km\arm64" ntoskrnl.lib hal.lib wdmsec.lib BufferOverflowFastFailK.lib libcntpr.lib
if errorlevel 1 (echo link failed & exit /b 1)
echo built out\dbgcap.sys
exit /b 0


