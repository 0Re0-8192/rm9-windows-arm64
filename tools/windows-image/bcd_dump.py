"""bcd_dump.py <BCD file> : print every BCD object with its elements (hivex).  Run in WSL: /root/.venv/bin/python3 bcd_dump.py <file>"""
import sys
import hivex

h = hivex.Hivex(sys.argv[1])
root = h.root()
objs = h.node_get_child(root, "Objects")
for o in h.node_children(objs):
    name = h.node_name(o)
    el = h.node_get_child(o, "Elements")
    desc = h.node_get_child(o, "Description")
    typ = None
    if desc is not None:
        for v in h.node_values(desc):
            if h.value_key(v) == "Type":
                typ = h.value_dword(v)
    print("OBJECT", name, "type=%s" % (hex(typ) if typ is not None else None))
    if el is None:
        continue
    for e in h.node_children(el):
        for v in h.node_values(e):
            if h.value_key(v) == "Element":
                t, raw = h.value_type(v)
                data = h.node_value_data = None
                try:
                    b = h.value_value(v)[1]
                except Exception:
                    b = b""
                txt = ""
                try:
                    s = b.decode("utf-16le", "ignore").strip("\0")
                    if len(s) > 1 and s.isprintable():
                        txt = " str=" + s
                except Exception:
                    pass
                print("   %-10s %s%s" % (h.node_name(e), b[:24].hex(), txt))
