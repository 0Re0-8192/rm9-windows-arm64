#!/usr/bin/env python3
"""List what Windows enumerated (HKLM\\SYSTEM\\CurrentControlSet\\Enum) from a SYSTEM hive pulled off the phone.
usage: hive_enum.py SYSTEM.device [filter-substring]"""
import sys
import hivex

h = hivex.Hivex(sys.argv[1])
flt = sys.argv[2].lower() if len(sys.argv) > 2 else ""
root = h.root()
sel = h.node_get_child(root, "Select")
cur = {h.value_key(v): h.value_value(v)[1] for v in h.node_values(sel)}
cs = "ControlSet%03d" % int.from_bytes(cur["Current"], "little")
enum = h.node_get_child(h.node_get_child(root, cs), "Enum")


def vals(n):
    d = {}
    for v in h.node_values(n):
        t, b = h.value_value(v)
        k = h.value_key(v)
        if t in (1, 2):
            d[k] = b.decode("utf-16le", "replace").rstrip("\0")
        elif t == 4:
            d[k] = int.from_bytes(b[:4], "little")
        elif t == 7:
            d[k] = b.decode("utf-16le", "replace").replace("\0", "|").strip("|")
        else:
            d[k] = "<%d bytes>" % len(b)
    return d


n = 0
for bus in h.node_children(enum):
    bname = h.node_name(bus)
    for dev in h.node_children(bus):
        dname = h.node_name(dev)
        for inst in h.node_children(dev):
            path = "%s\\%s\\%s" % (bname, dname, h.node_name(inst))
            v = vals(inst)
            line = "%s | svc=%s | class=%s | %s | cfg=%s prob=%s" % (path, v.get("Service", ""), v.get("Class", ""), v.get("DeviceDesc", "").split(";")[-1],
                                                              v.get("ConfigFlags", ""), v.get("Problem", ""))
            if flt in line.lower():
                print(line)
                n += 1
print("-- %d device instances%s" % (n, " matching '%s'" % flt if flt else ""))
