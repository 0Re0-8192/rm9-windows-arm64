#!/bin/bash
# download the three UUP esd files (Windows 11 26H1 28000.3086 arm64 Pro) that hold the original SystemApps; verify sha1
mkdir -p /root/uup_apps && cd /root/uup_apps
while IFS=$'\t' read -r name size sha url; do
  [ -z "$name" ] && continue
  echo "== $name $size $(date +%H:%M:%S)"
  curl -sS -L --retry 5 -C - -o "$name" "$url"
  got=$(sha1sum "$name" | cut -d' ' -f1)
  [ "$got" = "$sha" ] && echo "OK $name" || echo "SHA MISMATCH $name got=$got want=$sha"
done < <RM9_WORKDIR>/refs/uup_apps_urls.txt
echo "ALL DONE $(date +%H:%M:%S)"
