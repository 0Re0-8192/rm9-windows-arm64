import re, os
root = r"<RM9_WORKDIR>\uefi_extract2\BOOT.MXF.2.1-01643.1-LANAI-1.46586.3"
for rel in [r"QcomPkg\Drivers\QcomBds\QcomBds.efi", r"QcomPkg\Drivers\NubiaBoardDxe\NubiaBoardDxe.efi"]:
    p = os.path.join(root, rel)
    print("=" * 70)
    print(os.path.basename(p), os.path.getsize(p))
    d = open(p, "rb").read()
    seen = []
    for m in re.finditer(rb"[\x20-\x7e]{5,}", d):
        s = m.group().decode("latin1")
        if s not in seen:
            seen.append(s)
    print("unique ascii strings:", len(seen))
    kw = re.compile(r"boot|slot|devinfo|fastboot|recovery|load|fail|error|once|gpt|attr|partition|kernel|avb|verify|ufs|lun|misc|android", re.I)
    hits = [s for s in seen if kw.search(s) and len(s) > 6]
    for s in hits[:110]:
        print("   ", s)
