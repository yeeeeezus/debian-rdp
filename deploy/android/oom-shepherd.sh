#!/bin/bash
# oom-shepherd — keep the auto-reviving services marked as preferred OOM
# victims (oom_score_adj=800) so memory squeezes kill a service that the
# supervisor brings back in ~6s instead of the X session or the Android
# emulator (which costs 20+ min to reboot under software emulation).
# Started detached by android-runtime.sh; survives on its own session.
while true; do
  for pid in $(pgrep -f 'websockify|front-proxy|rdp-keepalive|rdp-save-daemon' 2>/dev/null); do
    [ "$pid" = "$$" ] && continue
    cur=$(cat /proc/$pid/oom_score_adj 2>/dev/null)
    if [ "${cur:-0}" != "800" ]; then
      echo 800 > /proc/$pid/oom_score_adj 2>/dev/null
    fi
  done
  sleep 20
done
