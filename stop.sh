#!/bin/bash

WANNUM=2

dhcp/sbin/dhclient -cf dhclient.conf -sf script.sh -pf /root/wan${WANNUM}/dhclient.pid -4 wan${WANNUM} -d -v -r
sleep 1
brctl delif WAN wan${WANNUM}br
ifconfig wan${WANNUM}br down
ifconfig wan${WANNUM} down
ip link del wan${WANNUM}br
ip route flush table wan${WANNUM}
ip rule show | grep "wan${WANNUM}"  | while read PRIO RULE; do   ip rule del prio ${PRIO%%:*} $( echo $RULE | sed 's|all|0/0|' ); done
