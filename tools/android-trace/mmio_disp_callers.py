"""Per-caller summary of the screen-ON window: first time, count, writes, address range (virtual page clusters)."""
import re
from collections import OrderedDict

src = r"<RM9_WORKDIR>\winboot\mmio_disp.txt"
pat = re.compile(r"\s(\d+\.\d+): rwmmio_(read|write): (\S+?)\+0x[0-9a-f]+/0x[0-9a-f]+ (?:\[(\S+)\] )?.*?width=(\d+) (?:val=(0x[0-9a-f]+) )?addr=(0x[0-9a-f]+)")
on = None
d = OrderedDict()
for ln in open(src, encoding="utf-8", errors="replace"):
    if "RM9_MARK_SCREEN_ON" in ln:
        on = float(re.search(r"(\d+\.\d+):", ln).group(1))
        continue
    if on is None:
        continue
    m = pat.search(ln)
    if not m:
        continue
    t = float(m.group(1)) - on
    key = (m.group(4) or "-", m.group(3))
    e = d.setdefault(key, [t, 0, 0, set()])
    e[1] += 1
    if m.group(2) == "write":
        e[2] += 1
    e[3].add(int(m.group(7), 16) >> 16)
skip = {"gic_mask_irq", "gic_unmask_irq", "gic_cpu_pm_notifier", "gic_enable_redist", "__tcs_buffer_write", "__tcs_set_trigger", "tcs_tx_done",
        "rpmh_rsc_update_fast_path"}
for (mod, fn), (t, n, w, pages) in sorted(d.items(), key=lambda kv: kv[1][0]):
    if fn in skip or mod in ("msm_gpi", "qcom_pdc", "pinctrl_msm", "qcom_cpufreq_hw", "qcom_llcc_pmu", "bwmon", "qcom_pmu_lib"):
        continue
    print("%8.4f %-12s %-44s n=%-6d w=%-6d pages=%s" % (t, mod, fn, n, w, ",".join("%x" % p for p in sorted(pages)[:6])))
