#!/usr/bin/env python3
"""List boot/system-start services, CrashControl and Setup values of a SYSTEM hive copy (python hivex).  hive_boot_audit.py SYSTEM"""
import sys
import hivex

h = hivex.Hivex(sys.argv[1])
root = h.root()
sel = h.node_get_child(root, "Select")
cur = 1
for v in h.node_values(sel):
    if h.value_key(v) == "Current":
        cur = h.value_dword(v)
cs = "ControlSet%03d" % cur
print("current", cs)
ctl = h.node_get_child(h.node_get_child(root, cs), "Control")
svc = h.node_get_child(h.node_get_child(root, cs), "Services")


def vals(n):
    out = {}
    for v in h.node_values(n):
        k = h.value_key(v)
        t, raw = h.value_value(v)
        if t == 4:
            out[k] = int.from_bytes(raw[:4], "little")
        elif t in (1, 2):
            out[k] = raw.decode("utf-16le", "ignore").rstrip("\x00")
        elif t == 7:
            out[k] = raw.decode("utf-16le", "ignore").replace("\x00", "|")
        else:
            out[k] = raw[:16].hex()
    return out


print("== CrashControl", vals(h.node_get_child(ctl, "CrashControl")))
for name in ("Session Manager",):
    n = h.node_get_child(ctl, name)
    print("==", name, {k: v for k, v in vals(n).items() if k in ("BootExecute", "PendingFileRenameOperations", "SetupExecute")})
print("== Setup", vals(h.node_get_child(root, "Setup")))
print("== Services with Start<=1 (name start group imagepath), plus rm9*/vhf")
for c in h.node_children(svc):
    n = h.node_name(c)
    v = vals(c)
    s = v.get("Start")
    if s in (0, 1) or n.lower().startswith(("rm9", "vhf", "wintun", "usbdk", "dedicated")):
        print("  %-28s start=%s type=%s group=%s img=%s" % (n, s, v.get("Type"), v.get("Group"), v.get("ImagePath")))
