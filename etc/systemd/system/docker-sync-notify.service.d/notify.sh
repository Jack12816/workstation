#!/bin/bash

# Fetch the size of the docker repository
SIZE=$(du -hs /var/lib/docker/ | awk '{print $1}')
SUNIT=$(echo "${SIZE}B" | rev | cut -c1-2 | rev)
SIZE=$(echo "$(echo "${SIZE}" | grep -oP '[0-9]+') ${SUNIT}")

# Fetch the needed time to sync
TIME=$(systemd-analyze blame | grep 'asd.service' \
  | sed 's/asd.service//g' | xargs)

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
