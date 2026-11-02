#!/usr/bin/env python3
"""Summarize the hardware nodes of the NX769J device tree: node name, compatible, reg (first range), status.  Groups them by function."""
import re
import sys
from collections import defaultdict

p = "/root/Mu-Silicium/Resources/DTBs/nx769j.dts"
txt = open(p, encoding="utf-8", errors="replace").read()
# very small DTS walker: track node names by brace depth
nodes = []
stack = []
cur_props = {}
for raw in txt.split("\n"):
    line = raw.strip()
    m = re.match(r"^([\w\-,\.@]+(?:\s*:\s*[\w\-,\.@]+)?)\s*\{$", line) or re.match(r"^(\w+:\s*[\w\-,\.@]+)\s*\{$", line)
    if line.endswith("{") and not line.startswith("/*"):
        name = line[:-1].strip()
        stack.append(name)
        cur_props = {}
        nodes.append((list(stack), cur_props))
        continue
    if line.startswith("};"):
        if stack:
            stack.pop()
        cur_props = nodes[-1][1] if False else {}
        continue
    pm = re.match(r'^(compatible|reg|status)\s*=\s*(.*);$', line)
    if pm and nodes:
        nodes[-1][1][pm.group(1)] = pm.group(2)

groups = defaultdict(list)
KEYS = [
    ("display/panel", r"dsi|panel|mdss|dpu|display"), ("touch/input", r"touch|goodix|focal|synaptics|fts|gpio-keys|input"),
    ("battery/charger/PMIC glink", r"glink|battery|charger|fg|bms|smb|pmic-glink|usb-pdphy|typec"),
    ("thermal/TSENS", r"tsens|thermal"), ("RTC", r"rtc"), ("PCIe", r"pcie"), ("Wi-Fi/BT", r"wcn|wlan|bluetooth|ath|qca|cnss"),
    ("audio", r"audio|wcd|lpass|wsa|swr|sound|q6|aud"), ("camera", r"cam|csiphy|sensor-|isp"), ("sensors/ssc", r"ssc|iio|accel|gyro|prox|als|mag"),
    ("GPU", r"kgsl|gpu|adreno|gmu"), ("USB", r"usb|dwc3|qmp|snps"), ("storage", r"ufs|sdhc|mmc|ice"), ("GPIO/pinctrl/I2C/SPI/UART", r"tlmm|pinctrl|i2c|spi|uart|geni|qup|serial"),
    ("clocks/power", r"clock|gcc|rpmh|regulator|pdc|aoss|llcc|bus|interconnect|icc|smmu|iommu|cpufreq|cpu"), ("modem/DSP/remoteproc", r"remoteproc|modem|adsp|cdsp|mpss|ipcc|smem|glink"),
    ("NFC/fingerprint/vibrator/LED", r"nfc|fingerprint|vibrator|haptic|led|flash|fan|cooling")]
for path, props in nodes:
    comp = props.get("compatible", "")
    nm = path[-1]
    if not comp:
        continue
    key = "other"
    for k, rx in KEYS:
        if re.search(rx, comp, re.I) or re.search(rx, nm, re.I):
            key = k
            break
    reg = props.get("reg", "").replace("<", "").replace(">", "")
    groups[key].append("%-38s %-52s %s" % (nm[:38], comp.replace('"', "")[:52], reg[:44]))
for k in [x[0] for x in KEYS] + ["other"]:
    if groups.get(k):
        print("\n## %s (%d)" % (k, len(groups[k])))
        for l in groups[k][:14]:
            print("  " + l)
        if len(groups[k]) > 14:
            print("  ... +%d more" % (len(groups[k]) - 14))
