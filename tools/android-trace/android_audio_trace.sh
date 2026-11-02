T=/sys/kernel/tracing
cd $T
input keyevent KEYCODE_BACK; sleep 2
echo 0 > tracing_on; echo > trace; echo 131072 > buffer_size_kb; echo 0 > events/enable
echo 1 > events/rwmmio/rwmmio_write/enable
echo 1 > events/i2c/enable
echo 1 > events/asoc/enable
echo 1 > tracing_on
am start -n com.google.android.apps.nbu.files/.gateway.preview.PreviewActivity -a android.intent.action.VIEW -d file:///sdcard/Download/tone8.wav -t audio/wav > /dev/null 2>&1
sleep 11
echo 0 > tracing_on
cp trace /data/local/tmp/aud_trace3.txt
echo 0 > events/enable
wc -l /data/local/tmp/aud_trace3.txt
grep -c i2c_write /data/local/tmp/aud_trace3.txt
grep -c snd_soc /data/local/tmp/aud_trace3.txt
input keyevent KEYCODE_BACK
