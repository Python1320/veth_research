#!/bin/bash

WANNUM=2

resolvconfprint() {
	echo resolvconf
}

# run given script
run_hook() {
    local script
    local exit_status
    script="$1"
    shift	# discard the first argument, then the rest are the script's

    if [ -f $script ]; then
        . $script "$@"
    fi

    if [ -n "$exit_status" ] && [ "$exit_status" -ne 0 ]; then
        logger -p daemon.err "$script returned non-zero exit status $exit_status"
    fi

    return $exit_status
}

# run scripts in given directory
run_hookdir() {
    local dir
    local exit_status
    dir="$1"
    shift	# See run_hook

    if [ -d "$dir" ]; then
        for script in $(run-parts --list $dir); do
            run_hook $script "$@" || true
            exit_status=$?
        done
    fi

    return $exit_status
}

# Must be used on exit.   Invokes the local dhcp client exit hooks, if any.
exit_with_hooks() {
    exit_status=$1

    # Source the documented exit-hook script, if it exists
   # if ! run_hook /etc/dhcp/dhclient-exit-hooks "$@"; then
   #     exit_status=$?
   # fi

    # Now run scripts in the Debian-specific directory.
   # if ! run_hookdir /etc/dhcp/dhclient-exit-hooks.d "$@"; then
    #    exit_status=$?
   # fi

    exit $exit_status
}


# set up some variables for DHCPv4 handlers below
if [ -n "$new_broadcast_address" ]; then
    new_broadcast_arg="broadcast $new_broadcast_address"
fi
if [ -n "$old_broadcast_address" ]; then
    old_broadcast_arg="broadcast $old_broadcast_address"
fi
if [ -n "$new_subnet_mask" ]; then
    new_mask="/$new_subnet_mask"
fi
if [ -n "$alias_subnet_mask" ]; then
    alias_mask="/$alias_subnet_mask"
fi


if [ -z "$new_interface_mtu" ] || [ "$new_interface_mtu" -lt 576 ]; then
    new_interface_mtu=''
fi
if [ -n "$IF_METRIC" ]; then
    metric_arg="metric $IF_METRIC"	# interfaces(5), "metric" option
fi


# The action starts here

# Invoke the local dhcp client enter hooks, if they exist.
#run_hook /etc/dhcp/dhclient-enter-hooks
#run_hookdir /etc/dhcp/dhclient-enter-hooks.d

# Execute the operation
echo "$reason"
case "$reason" in

    ### DHCPv4 Handlers

    MEDIUM)
        echo "NOP: $reason - if: $interface medium: $medium"
	;;
    ARPCHECK|ARPSEND)
        echo "NOP: $reason"
        ;;
    PREINIT)

        # The DHCP client is requesting that an interface be
        # configured as required in order to send packets prior to
        # receiving an actual address. - dhclient-script(8)

        # ensure interface is up
        ip link set dev ${interface} up

        if [ -n "$alias_ip_address" ]; then
            # flush alias IP from interface
            ip -4 addr flush dev ${interface} label ${interface}:0
        fi

        ;;
    BOUND|RENEW|REBIND|REBOOT)
        if [ -n "$old_host_name" ] && [ ! -s /etc/hostname ]; then
            # hostname changed => set it
            echo hostname "$new_host_name"
        fi

        if [ -n "$old_ip_address" ] && [ -n "$alias_ip_address" ] &&
           [ "$alias_ip_address" != "$old_ip_address" ]; then
            # alias IP may have changed => flush it
            ip -4 addr flush dev ${interface} label ${interface}:0
        fi

        if [ -n "$old_ip_address" ] &&
           [ "$old_ip_address" != "$new_ip_address" ]; then
            # leased IP has changed => flush it
            ip -4 addr flush dev ${interface} label ${interface}
        fi

        if [ -z "$old_ip_address" ] ||
           [ "$old_ip_address" != "$new_ip_address" ] ||
           [ "$reason" = "BOUND" ] || [ "$reason" = "REBOOT" ]; then
            # new IP has been leased or leased IP changed => set it
            echo "ip -4 addr add ${new_ip_address}${new_mask} ${new_broadcast_arg} dev ${interface} label ${interface}"
            ip -4 addr add ${new_ip_address}${new_mask} ${new_broadcast_arg} dev ${interface} label ${interface}
	    echo "ip rule add from ${new_ip_address} table wan${WANNUM}"
	    ip rule add from ${new_ip_address} table wan${WANNUM}

            if [ -n "$new_interface_mtu" ]; then
                # set MTU
                ip link set dev ${interface} mtu ${new_interface_mtu}
            fi

            for router in $new_routers; do
				echo "Route: $router"
                if [ "$new_subnet_mask" = "255.255.255.255" ]; then
                    echo "   point-to-point connection => set explicit route"
                    echo "ip -4 route add ${router} dev $interface table wan${WANNUM}"
                    ip -4 route add ${router} dev $interface table wan${WANNUM}
                fi

                echo "ip -4 route add default via ${router} dev ${interface} ${metric_arg}  table wan${WANNUM}"
                
                ip -4 route add default via ${router} dev ${interface} ${metric_arg}  table wan${WANNUM}
            done
        fi

        if [ -n "$alias_ip_address" ] &&
           [ "$new_ip_address" != "$alias_ip_address" ]; then
            # separate alias IP given, which may have changed
            # => flush it, set it & add host route to it
            ip -4 addr flush dev ${interface} label ${interface}:0
            ip -4 addr add ${alias_ip_address} ${alias_mask} \
                dev ${interface} label ${interface}:0
           echo "ip -4 route add ${alias_ip_address} dev ${interface}  table wan${WANNUM}"
            ip -4 route add ${alias_ip_address} dev ${interface}  table wan${WANNUM}
        fi
        resolvconfprint

        ;;

    EXPIRE|FAIL|RELEASE|STOP)
        if [ -n "$alias_ip_address" ]; then
            # flush alias IP
            ip -4 addr flush dev ${interface} label ${interface}:0
        fi

        if [ -n "$old_ip_address" ]; then
            # flush leased IP
            ip -4 addr flush dev ${interface} label ${interface}
        fi

        if [ -n "$alias_ip_address" ]; then
            # alias IP given => set it & add host route to it
            ip -4 addr add ${alias_ip_address}${alias_network_arg} \
                dev ${interface} label ${interface}:0
            echo "ip -4 route add ${alias_ip_address} dev ${interface} table wan${WANNUM}"
			ip -4 route add ${alias_ip_address} dev ${interface} table wan${WANNUM}
        fi

        ;;

    TIMEOUT)
        if [ -n "$alias_ip_address" ]; then
            # flush alias IP
            ip -4 addr flush dev ${interface} label ${interface}:0
        fi

        # set IP from recorded lease
        ip -4 addr add ${new_ip_address}${new_mask} ${new_broadcast_arg} \
            dev ${interface} label ${interface}

        if [ -n "$new_interface_mtu" ]; then
            # set MTU
            ip link set dev ${interface} mtu ${new_interface_mtu}
        fi

        # if there is no router recorded in the lease or the 1st router answers pings
        if [ -z "$new_routers" ] || ping -q -c 1 "${new_routers%% *}"; then
            if [ -n "$alias_ip_address" ] &&
               [ "$new_ip_address" != "$alias_ip_address" ]; then
                # separate alias IP given => set up the alias IP & add host route to it
                ip -4 addr add ${alias_ip_address}${alias_mask} \
                    dev ${interface} label ${interface}:0
	
				echo "ip -4 route add ${alias_ip_address} dev ${interface} table wan${WANNUM}"
                ip -4 route add ${alias_ip_address} dev ${interface} table wan${WANNUM}
            fi

            # set default route
            for router in $new_routers; do
				echo "Default route: $router"
				echo "ip -4 route add default via ${router} dev ${interface}  ${metric_arg}  table wan${WANNUM}"
                ip -4 route add default via ${router} dev ${interface}  ${metric_arg}  table wan${WANNUM}
            done

            resolvconfprint
        else
            # flush all IPs from interface
            ip -4 addr flush dev ${interface}
            exit_with_hooks 2 "$@"
        fi

        ;;

    ### DHCPv6 Handlers
    # TODO handle prefix change: ?based on ${old_ip6_prefix} and ${new_ip6_prefix}?

    PREINIT6)
        # ensure interface is up
        ip link set ${interface} up

        # flush any stale global permanent IPs from interface
        ip -6 addr flush dev ${interface} scope global permanent

        ;;

    BOUND6|RENEW6|REBIND6)
        if [ -z "${new_ip6_address}" ] || [ -z "${new_ip6_prefixlen}" ]; then
            exit_with_hooks 2
        fi

        # set leased IP
        ip -6 addr add ${new_ip6_address}/${new_ip6_prefixlen} \
            dev ${interface} scope global

        # update /etc/resolv.conf
        if [ "${reason}" = BOUND6 ] ||
           [ "${new_dhcp6_name_servers}" != "${old_dhcp6_name_servers}" ] ||
           [ "${new_dhcp6_domain_search}" != "${old_dhcp6_domain_search}" ]; then
            resolvconfprint
        fi

        ;;

    DEPREF6)
        if [ -z "${cur_ip6_prefixlen}" ]; then
            exit_with_hooks 2
        fi

        # set preferred lifetime of leased IP to 0
        ip -6 addr change ${cur_ip6_address}/${cur_ip6_prefixlen} \
            dev ${interface} scope global preferred_lft 0

        ;;

    EXPIRE6|RELEASE6|STOP6)
        if [ -z "${old_ip6_address}" ] || [ -z "${old_ip6_prefixlen}" ]; then
            exit_with_hooks 2
        fi

        # delete leased IP
        ip -6 addr del ${old_ip6_address}/${old_ip6_prefixlen} \
            dev ${interface}

        ;;
	*)
	echo "NOOP: $reason"
	;;
esac

exit_with_hooks 0
