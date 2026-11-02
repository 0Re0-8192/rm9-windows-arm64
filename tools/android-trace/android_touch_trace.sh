#!/system/bin/sh
# WARNING: unbind/bind of gtx8_spi makes the driver re-flash the touch IC firmware (succeeded once, 2026-10-16). Do not run casually.
# Capture the Goodix BRL-D (gtx8_spi, spi1.0) SPI traffic during a driver re-probe (unbind/bind) using the spi tracepoints. No physical interaction needed.
T=/sys/kernel/tracing
O=/data/local/tmp/touch
D=/sys/bus/spi/devices/spi1.0
mkdir -p $O
echo 0 > $T/tracing_on
echo > $T/trace
echo 65536 > $T/buffer_size_kb
echo 'bus_num==1' > $T/events/spi/spi_transfer_stop/filter
echo 1 > $T/events/spi/spi_transfer_stop/enable
echo 1 > $T/events/spi/spi_setup/enable
echo 1 > $T/events/spi/spi_set_cs/enable
{ for p in $D/of_node/*; do echo "== $p"; cat $p | od -An -tx1 | head -8; done; } > $O/of_props.txt 2>&1
getevent -p 2>/dev/null | grep -B1 -A12 -i "goodix\|gtx" > $O/getevent.txt
echo 1 > $T/tracing_on
echo spi1.0 > /sys/bus/spi/drivers/gtx8_spi/unbind
sleep 2
echo spi1.0 > /sys/bus/spi/drivers/gtx8_spi/bind
sleep 8
echo 0 > $T/tracing_on
cp $T/trace $O/trace.txt
echo 0 > $T/events/spi/spi_transfer_stop/enable
echo 0 > $T/events/spi/spi_setup/enable
echo 0 > $T/events/spi/spi_set_cs/enable
echo > $T/events/spi/spi_transfer_stop/filter
dmesg | grep -iE "gtx8|goodix|brl|touch" | tail -80 > $O/dmesg_touch.txt
wc -l $O/*
