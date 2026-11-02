cd /root
SECS=33442999
rm -f /root/win.img
truncate -s $((SECS*4096)) /root/win.img
mkntfs -F -Q -s 4096 -c 4096 -H 255 -S 63 -L Windows -p 28078888 /root/win.img 2>&1 | tail -2
echo "== mkntfs done $(date)"
wimlib-imagex apply /root/uup/files/professional_en-us.esd 3 /root/win.img --ref="/root/uup/files/*.esd" --ref=/root/cabs.wim 2>&1 | tr '\r' '\n' | awk '/ERROR|WARN|Done|Applying|blob/ || NR%50==0'
echo "== apply done $(date)"
du -sh --apparent-size /root/win.img; du -sh /root/win.img