@echo off
rem display probe: resolution Windows uses on the panel
set L=C:\rm9
call S:\rm9\timesync.cmd
echo ==== run.cmd start %date% %time%
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_VideoController | Format-List Name,CurrentHorizontalResolution,CurrentVerticalResolution,CurrentBitsPerPixel,AdapterRAM,VideoModeDescription,VideoProcessor"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class D{[StructLayout(LayoutKind.Sequential,CharSet=CharSet.Ansi)]public struct M{[MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)]public string n;public ushort sv,dv,sz,de;public uint f;public short pox,poy;public uint dor,dfo;[MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)]public string fn;public ushort lg;public uint bpp,w,h,dfl,dfr;public uint a,b,c,d,e,g;}[DllImport(\"user32.dll\")]public static extern bool EnumDisplaySettings(string d,int i,ref M m);}'; $m=New-Object D+M; $m.sz=[Runtime.InteropServices.Marshal]::SizeOf($m); $i=0; while([D]::EnumDisplaySettings($null,$i,[ref]$m)){ '{0}: {1}x{2} {3}bpp' -f $i,$m.w,$m.h,$m.bpp; $i++ }; [D]::EnumDisplaySettings($null,-1,[ref]$m) | Out-Null; 'current: {0}x{1}' -f $m.w,$m.h"
reg query "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration" /s
reg query "HKLM\HARDWARE\DEVICEMAP\VIDEO"
echo ==== run.cmd done %date% %time%
shutdown /a
shutdown /r /t 3 /f
