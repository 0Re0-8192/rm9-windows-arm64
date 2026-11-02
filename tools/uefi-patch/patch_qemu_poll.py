"""run_qemu_test.py: after the screenshot list, keep polling disk2's GPT header every 60 s until TOTAL (or QEMU exit)."""
from pathlib import Path

p = Path(r"<RM9_WORKDIR>\refs\run_qemu_test.py")
t = p.read_text(encoding="utf-8")
old = "while time.time() - t0 < TOTAL and p.poll() is None:\n    time.sleep(1)\n"
new = ("last_poll = 0\n"
       "while time.time() - t0 < TOTAL and p.poll() is None:\n"
       "    time.sleep(1)\n"
       "    if EXTRA and time.time() - last_poll >= 60:\n"
       "        last_poll = time.time()\n"
       "        import struct\n"
       "        with open(EXTRA, 'rb') as fx:\n"
       "            fx.seek(4096); h = fx.read(92)\n"
       "        if h[:8] == b'EFI PART':\n"
       "            my, alt, fu, lu = struct.unpack_from('<QQQQ', h, 24); el = struct.unpack_from('<Q', h, 72)[0]\n"
       "            print('t=%ds disk2 GPT: entriesLBA=%d first=%d last=%d' % (time.time() - t0, el, fu, lu), flush=True)\n"
       "        else:\n"
       "            print('t=%ds disk2 GPT: NO SIGNATURE' % (time.time() - t0), flush=True)\n")
assert old in t
t = t.replace(old, new, 1) if "last_poll" not in t else t
p.write_text(t, encoding="utf-8")
print("ok")
