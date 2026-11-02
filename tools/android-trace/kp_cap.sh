T=/sys/kernel/tracing; [ -d $T ] || T=/sys/kernel/debug/tracing
cd $T
echo 0 > tracing_on
echo > kprobe_events
echo 'p:bcw battery_chg_write len=%x2 w0=+0(%x1):x32 w1=+4(%x1):x32 w2=+8(%x1):x32 w3=+12(%x1):x32 w4=+16(%x1):x32 w5=+20(%x1):x32 w6=+24(%x1):x32 w7=+28(%x1):x32' >> kprobe_events
echo 'p:bcr battery_chg_callback len=%x2 w0=+0(%x1):x32 w1=+4(%x1):x32 w2=+8(%x1):x32 w3=+12(%x1):x32 w4=+16(%x1):x32 w5=+20(%x1):x32 w6=+24(%x1):x32 w7=+28(%x1):x32 w8=+32(%x1):x32 w9=+36(%x1):x32' >> kprobe_events
echo 1 > events/kprobes/bcw/enable
echo 1 > events/kprobes/bcr/enable
echo > trace
echo 1 > tracing_on
sleep ${1:-8}
echo 0 > tracing_on
cat trace | grep -E "bcw|bcr" | cut -c1-260 | head -${2:-80}
echo 0 > events/kprobes/bcw/enable; echo 0 > events/kprobes/bcr/enable
echo > kprobe_events
