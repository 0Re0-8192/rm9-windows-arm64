"""run_qemu_test.py: optional second NVMe disk from env EXTRA_DISK; at each screenshot, log that disk's primary
GPT header fields (entriesLBA, last usable, header signature) so rewrites by Windows are visible."""
from pathlib import Path

p = Path(r"<RM9_WORKDIR>\refs\run_qemu_test.py")
t = p.read_text(encoding="utf-8")
if "EXTRA_DISK" not in t:
    t = t.replace('if len(sys.argv) > 2 and sys.argv[2] == "pe":',
                  'EXTRA = os.environ.get("EXTRA_DISK")\n'
                  'if EXTRA:\n'
                  '    cmd += ["-drive", "file=" + EXTRA + ",if=none,id=d1,format=raw",\n'
                  '            "-device", "nvme,drive=d1,serial=disk2,logical_block_size=4096,physical_block_size=4096"]\n'
                  'if len(sys.argv) > 2 and sys.argv[2] == "pe":', 1)
    t = t.replace('    print("shot", s, flush=True)',
                  '    print("shot", s, flush=True)\n'
                  '    if EXTRA:\n'
                  '        import struct\n'
                  '        with open(EXTRA, "rb") as fx:\n'
                  '            fx.seek(4096); h = fx.read(92)\n'
                  '        if h[:8] == b"EFI PART":\n'
                  '            my, alt, fu, lu = struct.unpack_from("<QQQQ", h, 24); el = struct.unpack_from("<Q", h, 72)[0]\n'
                  '            print("  disk2 GPT: entriesLBA=%d first=%d last=%d" % (el, fu, lu), flush=True)\n'
                  '        else:\n'
                  '            print("  disk2 GPT: NO SIGNATURE", flush=True)', 1)
    p.write_text(t, encoding="utf-8")
print("ok", "EXTRA_DISK" in t)
