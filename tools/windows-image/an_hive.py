"""an_hive.py <hive> <key/path> ...  : print the values of registry keys (use / as the path separator)."""
import sys
import hivex

h = hivex.Hivex(sys.argv[1])


def walk(path):
    n = h.root()
    for p in path.split('/'):
        n = h.node_get_child(n, p)
        if n is None:
            return None
    return n


def vals(path):
    n = walk(path)
    if n is None:
        print(path, '-> (missing)')
        return
    for v in h.node_values(n):
        k = h.value_key(v)
        t, raw = h.value_type(v)
        try:
            if t in (1, 2):
                val = h.value_string(v)
            elif t == 7:
                val = h.value_multiple_strings(v)
            elif t == 4:
                val = h.value_dword(v)
            else:
                val = raw
        except Exception:
            val = '?'
        print('  ', k, '=', val)


for p in sys.argv[2:]:
    print(p)
    vals(p)
