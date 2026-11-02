@echo off
rem Build rm9irq.sys (KMDF, claims the Wi-Fi chip's MBI SPIs) for ARM64.   usage: build.bat   (from drv\rm9irq)
setlocal
set WDK=C:\Program Files (x86)\Windows Kits\10
set WV=10.0.26100.0
set KV=1.31
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsamd64_arm64.bat" >nul
if errorlevel 1 (echo vcvars failed & exit /b 1)
if not exist out mkdir out
cl /nologo /kernel /GS- /W3 /O2 /Zi /c /D_ARM64_ /DARM64 /D_WIN64 /DNTDDI_VERSION=0x0A00000C /D_WIN32_WINNT=0x0A00 /DWINVER=0x0A00 /DPOOL_NX_OPTIN=1 /DKMDF_VERSION_MAJOR=1 /DKMDF_VERSION_MINOR=31 ^
   /I"%WDK%\Include\%WV%\km" /I"%WDK%\Include\%WV%\shared" /I"%WDK%\Include\wdf\kmdf\%KV%" /Fo:out\ rm9irq.c
if errorlevel 1 (echo compile failed & exit /b 1)
link /nologo /DRIVER:WDM /SUBSYSTEM:NATIVE /ENTRY:FxDriverEntry /NODEFAULTLIB /MACHINE:ARM64 /OUT:out\rm9irq.sys /PDB:out\rm9irq.pdb out\rm9irq.obj ^
   /LIBPATH:"%WDK%\Lib\%WV%\km\arm64" /LIBPATH:"%WDK%\Lib\wdf\kmdf\arm64\%KV%" ntoskrnl.lib hal.lib wdmsec.lib WdfDriverEntry.lib WdfLdr.lib ntstrsafe.lib BufferOverflowFastFailK.lib libcntpr.lib
if errorlevel 1 (echo link failed & exit /b 1)
echo built out\rm9irq.sys
exit /b 0
