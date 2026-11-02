import re
import sys

src = r"<RM9_WORKDIR>\winboot\mmio_win.txt"
mk = {}
for ln in open(src, encoding="utf-8", errors="replace"):
    if "RM9_MARK" in ln:
        m = re.search(r"(\d+\.\d+): tracing_mark_write: (RM9_MARK_\w+)", ln) or re.search(r"(\d+\.\d+):.*(RM9_MARK_\w+)", ln)
        if m:
            mk[m.group(2)] = float(m.group(1))
print(mk)
t0 = mk.get("RM9_MARK_INSMOD", 0)
t1 = float(sys.argv[1]) if len(sys.argv) > 1 else 410.2466
want = sys.argv[2] if len(sys.argv) > 2 else "cnss2|crm|qcom_rpmh|pinctrl_msm|btpower|rpmh_regulator|gcc|clk_qcom|tcsrcc"
pat = re.compile(r"\s(\d+\.\d+): rwmmio_(read|write): (\S+?)\+0x[0-9a-f]+/0x[0-9a-f]+ (?:\[(\S+)\] )?.*?width=(\d+) (?:val=(0x[0-9a-f]+) )?addr=(0x[0-9a-f]+)")
cnt = {}
for ln in open(src, encoding="utf-8", errors="replace"):
    m = pat.search(ln)
    if not m:
        continue
    t = float(m.group(1))
    if t < t0 or t > t1:
        continue
    mod = m.group(4) or "-"
    cnt[mod] = cnt.get(mod, 0) + 1
    if re.search(want, mod) and m.group(2) == "write":
        print("%.6f W %-30s %-14s val=%-12s addr=%s" % (t, m.group(3), mod, m.group(6) or "", m.group(7)))
print("module counts in window:", cnt, file=sys.stderr)
