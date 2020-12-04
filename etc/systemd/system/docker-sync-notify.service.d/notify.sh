#!/bin/bash

# Fetch the size of the docker repository
SIZE=$(du -hs /var/lib/docker/ \
  | awk '{print $1}' | sed 's/\([a-z]\+\)$/ \1B/gi')

# Fetch the needed time to sync (for some reason systemd-analyze is not yet
# ready to query, so we use the system uptime for time tracking)
TIME=$(awk '{print int(($1%3600)/60)"min "int($1%60)"."($1%1 * 100)"s"}' \
  /proc/uptime)

# Send a system notification to every logged in user (libnotify)
IFS=$'\n'
for LINE in `w -hs`; do
  USER=`echo $LINE | awk '{print $1}'`
  USER_ID=`id -u $USER`
  DISP_ID=`echo $LINE | awk '{print $8}'`
  sudo -u $USER \
    DISPLAY=$DISP_ID DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$USER_ID/bus \
    notify-send -t 5000 \
        'Docker service started' \
        "The RAM disk sync is done. $SIZE in $TIME." \
        --icon=yast-docker
done
