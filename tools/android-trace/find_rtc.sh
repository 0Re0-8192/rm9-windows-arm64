cd /root/Mu-Silicium
grep -rIn "RealTimeClockLib" Platforms/ZTE/nx769jPkg/nx769j.dsc Silicon/Silicium/SiliciumPkg/SiliciumPkg.dsc.inc 2>/dev/null | head -5
find . -ipath '*RealTimeClock*' -name '*.c' -not -path './Build/*' -not -path '*/Mu_Basecore/*' 2>/dev/null | head
