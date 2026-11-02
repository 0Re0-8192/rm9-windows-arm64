@echo off
rem S:\rm9\run.cmd = install + smoke-test the rm9io.sys kernel driver (test-signed; the phone runs Windows in Test Mode).
rem Files on the ESP (S:\rm9): rm9io.sys, rm9test.cer, rm9io.ps1, iotest.ps1
set L=C:\rm9
call S:\rm9\timesync.cmd
echo ==== io test start %date% %time%
certutil -addstore -f Root S:\rm9\rm9test.cer
certutil -addstore -f TrustedPublisher S:\rm9\rm9test.cer
sc stop rm9io
copy /y S:\rm9\rm9io.sys C:\Windows\System32\drivers\rm9io.sys
sc query rm9io | find "STATE" >nul || sc create rm9io type= kernel start= demand binPath= C:\Windows\System32\drivers\rm9io.sys
sc start rm9io
sc query rm9io
echo [iotest]
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\iotest.ps1
echo ==== io test done %date% %time%
shutdown /a
shutdown /r /t 3 /f
