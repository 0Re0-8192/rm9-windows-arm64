base = open('<RM9_WORKDIR>/refs/winpe/esp_run_session_usb15.cmd', encoding='utf-8', newline='').read().replace('\r\n', '\n')
add = open('<RM9_WORKDIR>/refs/winpe/touch_block.txt', encoding='utf-8', newline='').read().replace('\r\n', '\n')
marker = 'rem 4. replace the 10 minute backstop'
assert marker in base
out = base.replace(marker, add + marker, 1).replace('shutdown /r /t 900 /f', 'shutdown /r /t 420 /f')
open('<RM9_WORKDIR>/refs/winpe/esp_run_touch.cmd', 'w', encoding='utf-8', newline='').write(out.replace('\n', '\r\n'))
print('ok')
