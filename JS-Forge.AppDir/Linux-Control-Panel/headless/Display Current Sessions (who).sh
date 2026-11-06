#!/bin/bash
# who-rdp.sh
#   ./who-rdp.sh        watch (Ctrl-C to quit)
#   ./who-rdp.sh -1     one shot

INTERVAL=5

report () {
  rdpcollect=$(ps -eo user:12,pid,etime,comm --no-headers \
        | awk '$4=="xrdp-chansrv" { print $2 }')
  localcollect=$(who -a | awk '$(NF-1) ~ /^[0-9]+$/ {print $(NF-1)}')
  clear
  echo "Logged-on sessions  -  $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""
  echo "===================== Kick Commands ====================="
  echo "pkill -u $USER #ALL $USER sessions"
  #echo " kill -- -\$(ps -o pgid= -p $rdpcollect | xargs)"
  for p in $localcollect; do
  echo "kill -- -\$(ps -o pgid= -p $p | xargs) #Local/Console session"
  done
  for p in $rdpcollect; do
  echo "kill -- -\$(ps -o pgid= -p $p | xargs) #XRDP session"
  done

  echo
  echo "==================== LOCAL / CONSOLE ===================="
  who -a

  echo
  echo "==================== REMOTE (XRDP) ======================"
  rdp=$(ps -eo user:12,pid,etime,comm --no-headers \
        | awk '$4=="xrdp-chansrv" { printf "%-12s pid %-8s up %s\n", $1, $2, $3 }')
  if [ -n "$rdp" ]; then echo "$rdp"; else echo "(no RDP sessions)"; fi
}

if [ "$1" = "-1" ]; then
  report
else
  while :; do report; sleep "$INTERVAL"; done
fi