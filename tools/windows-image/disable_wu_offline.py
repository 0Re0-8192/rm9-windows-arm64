#!/usr/bin/env python3
"""Disable Windows Update in the offline phone image (mounted rw at <root>): service Start=4 for wuauserv/UsoSvc/WaaSMedicSvc (SYSTEM hive,
ControlSet001) and the AU/WindowsUpdate policies (SOFTWARE hive).  Refuses to touch a hive whose sequence numbers differ (dirty, needs log replay).
   disable_wu_offline.py /mnt/w"""
import struct
import sys
import hivex

root = sys.argv[1]
cfg = root + "/Windows/System32/config/"


def clean(p):
    with open(p, "rb") as f:
        h = f.read(512)
    s1, s2 = struct.unpack_from("<II", h, 4)
    print(p.split("/")[-1], "sequence", s1, s2)
    return s1 == s2


def setdw(h, node, name, val):
    for v in h.node_values(node):
        if h.value_key(v) == name:
            h.node_set_value(node, {"key": name, "t": 4, "value": val.to_bytes(4, "little")})
            return
    h.node_set_value(node, {"key": name, "t": 4, "value": val.to_bytes(4, "little")})


def ensure(h, node, path):
    for part in path:
        c = h.node_get_child(node, part)
        node = c if c else h.node_add_child(node, part)
    return node


sysp, swp = cfg + "SYSTEM", cfg + "SOFTWARE"
if not (clean(sysp) and clean(swp)):
    sys.exit("hive not clean: refusing")

h = hivex.Hivex(sysp, write=True)
svc = h.node_get_child(h.node_get_child(h.root(), "ControlSet001"), "Services")
for name in ("wuauserv", "UsoSvc", "WaaSMedicSvc"):
    n = h.node_get_child(svc, name)
    if n:
        setdw(h, n, "Start", 4)
        print("SYSTEM:", name, "Start=4")
    else:
        print("SYSTEM:", name, "not found")
h.commit(None)

h = hivex.Hivex(swp, write=True)
wu = ensure(h, h.root(), ["Policies", "Microsoft", "Windows", "WindowsUpdate"])
setdw(h, wu, "DoNotConnectToWindowsUpdateInternetLocations", 1)
setdw(h, wu, "DisableWindowsUpdateAccess", 1)
au = ensure(h, wu, ["AU"])
setdw(h, au, "NoAutoUpdate", 1)
setdw(h, au, "AUOptions", 1)
h.commit(None)
print("SOFTWARE: policies set")
