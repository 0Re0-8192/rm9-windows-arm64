#!/usr/bin/env python3
"""Make a copy of the phone's BCD with (or without) SafeBoot=Minimal (element 25000080 = 0) on the Windows loader object.
  bcd_safeboot.py in.bcd out.bcd on|off"""
import shutil
import sys
import hivex

src, dst, mode = sys.argv[1:4]
LOADER = "{cf7d2d5d-c719-11f1-9997-8a6d3b348e4f}"
shutil.copyfile(src, dst)
h = hivex.Hivex(dst, write=True)
els = h.node_get_child(h.node_get_child(h.node_get_child(h.root(), "Objects"), LOADER), "Elements")
cur = h.node_get_child(els, "25000080")
if mode == "on":
    if cur is None:
        cur = h.node_add_child(els, "25000080")
    h.node_set_value(cur, {"key": "Element", "t": 3, "value": (0).to_bytes(8, "little")})
else:
    if cur is not None:
        h.node_delete_child(cur)
h.commit(None)
print("done", mode, dst)
