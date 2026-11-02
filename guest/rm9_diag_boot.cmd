@echo off
rem C:\rm9\diag.cmd = fixed bootstrap (installed once into the NTFS image).  Everything else lives in S:\rm9\run.cmd on the ESP (FAT),
rem which can be edited from Android in seconds.  Runs as LocalSystem from the rm9diag service on every boot.
rem backstop first: restart after 10 minutes whatever happens (run.cmd may cancel/replace it with "shutdown /a")
shutdown /r /t 600 /f
if not exist C:\rm9 mkdir C:\rm9
echo boot %date% %time%> C:\rm9\boot.txt
mountvol S: /S >> C:\rm9\boot.txt 2>&1
if exist S:\rm9\run.cmd (
  echo run.cmd found>> C:\rm9\boot.txt
  call S:\rm9\run.cmd >> C:\rm9\run_out.txt 2>&1
  echo run.cmd returned %errorlevel%>> C:\rm9\boot.txt
) else (
  echo NO S:\rm9\run.cmd - restarting in 5 s>> C:\rm9\boot.txt
  shutdown /a
  shutdown /r /t 5 /f
)
