"""hook_bchk.py <dsl> : make every thermal zone's _TMP call \\_SB.BCHK () first (battery change detection -> Notify).  Idempotent."""
import sys

p = sys.argv[1]
s = open(p, encoding="utf-8").read()
NL = chr(10)
BS = chr(92)
head = "            Method (_TMP, 0, NotSerialized)" + NL + "            {" + NL
call = "                " + BS + "_SB.BCHK ()     // battery change detection (calls Notify)" + NL
n_all = s.count(head)
n_done = s.count(head + call)
if n_all == n_done:
    print("already hooked (%d)" % n_all)
else:
    s = s.replace(head + call, head)            # normalise, then add exactly once
    s = s.replace(head, head + call)
    open(p, "w", encoding="utf-8").write(s)
    print("BCHK () added to %d _TMP methods" % n_all)
