"""Read-only: which partition unique-GUIDs still collide between LUNs (live device)."""
import sys
sys.path.insert(0, r"<RM9_WORKDIR>\refs")
import gpt_unique_guids as g

seen = {}
for dev, lun in g.ALL.items():
    x = g.load(dev)
    for i, guid, name in g.entries(x["pe"]):
        seen.setdefault(guid, []).append((lun, name))
dups = {k: v for k, v in seen.items() if len(v) > 1}
print("partitions", sum(len(v) for v in seen.values()), "colliding GUIDs", len(dups))
for k, v in dups.items():
    print(" ", k, v)
luns_with_dups = sorted({l for v in dups.values() for l, _ in v})
print("LUNs involved in collisions:", luns_with_dups)
