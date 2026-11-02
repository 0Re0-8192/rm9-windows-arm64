#!/usr/bin/env python3
"""Stop a half-applied cumulative update from resuming on the next boot (offline image mounted rw at <root>):
  - rename WinSxS/pending.xml (the queued file operations of the update) to pending.xml.rm9off
  - SYSTEM hive: Services\TrustedInstaller Start=4 (servicing never starts)
   neutralize_update.py /mnt/w"""
import os
import struct
import sys
import hivex

root = sys.argv[1]
p = os.path.join(root, "Windows/WinSxS/pending.xml")
if os.path.exists(p):
    os.replace(p, p + ".rm9off")
    print("renamed pending.xml")
else:
    print("no pending.xml")
sysp = root + "/Windows/System32/config/SYSTEM"
s1, s2 = struct.unpack_from("<II", open(sysp, "rb").read(512), 4)
if s1 != s2:
    sys.exit("SYSTEM hive not clean")
h = hivex.Hivex(sysp, write=True)
svc = h.node_get_child(h.node_get_child(h.root(), "ControlSet001"), "Services")
for name in ("TrustedInstaller",):
    n = h.node_get_child(svc, name)
    h.node_set_value(n, {"key": "Start", "t": 4, "value": (4).to_bytes(4, "little")})
    print("SYSTEM:", name, "Start=4")
h.commit(None)
