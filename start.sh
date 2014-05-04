#!/bin/bash
#set -e
WANNUM=${1:-2}

echo Adding link wan${WANNUM}
ip link add name wan${WANNUM}br type veth peer name wan${WANNUM}
ip link set wan${WANNUM}br address "DE:EE:EE:EE:EE:E$WANNUM"
ip link set wan${WANNUM} address "DE:EE:EE:EE:EE:D$WANNUM"
echo Bringing up
ifconfig wan${WANNUM}br up
ifconfig wan${WANNUM} up

if [ -z "`cat /etc/iproute2/rt_tables | grep '^10${WANNUM}'`" ] ; then
   echo "10${WANNUM}    wan${WANNUM}" >> /etc/iproute2/rt_tables
fi

ip rule add fwmark 0x${WANNUM} table wan${WANNUM}

brctl addif WAN wan${WANNUM}br

ifconfig wan${WANNUM}br up
ifconfig wan${WANNUM} up

dhcp/sbin/dhclient -cf dhclient.conf -sf script.sh -pf /root/wan${WANNUM}/dhclient.pid -lf /root/wan${WANNUM}/leases.wan${WANNUM} -4 -s 255.255.255.255 -w -v wan${WANNUM}
echo done
