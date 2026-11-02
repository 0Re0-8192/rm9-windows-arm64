BS = chr(92)
base = open('<RM9_WORKDIR>/refs/winpe/esp_run_session_usb15.cmd', encoding='utf-8', newline='').read().replace('\r\n', '\n')
add = open('<RM9_WORKDIR>/refs/winpe/touchboot_block.txt', encoding='utf-8', newline='').read().replace('\r\n', '\n')
marker = 'rem 4. replace the 10 minute backstop'
assert marker in base
out = base.replace(marker, add + marker, 1)

guard = ('rem display driver trial guard: an experimental driver that did not reach ok.flag in its first boot is taken off again\n'
         'if exist C:' + BS + 'rm9' + BS + 'disp' + BS + 'trial.flag if not exist C:' + BS + 'rm9' + BS + 'disp' + BS + 'ok.flag powershell -NoProfile -ExecutionPolicy Bypass -File S:' + BS + 'rm9' + BS + 'dispguard.ps1\n')
k = 'call S:' + BS + 'rm9' + BS + 'timesync.cmd\n'
assert k in out
out = out.replace(k, k + guard, 1)

assert 'shutdown /r /t 900 /f' in out
out = out.replace('shutdown /r /t 900 /f', 'shutdown /r /t %BACK% /f')
open('<RM9_WORKDIR>/refs/winpe/esp_run_touchboot.cmd', 'w', encoding='utf-8', newline='').write(out.replace('\n', '\r\n'))
print('ok')
