#!/bin/bash
# greps the nx769j DTS for the addresses of the SCM IO_READ/IO_WRITE seen in the boot trace
grep -n -i -B6 -A6 -E "1fd9000|88e2000|0x17800000|0x1780[0-9a-f]{4} " /root/Mu-Silicium/Resources/DTBs/nx769j.dts | head -120
