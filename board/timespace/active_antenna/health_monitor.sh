#!/bin/sh

# log a message on syslog and on the serial port
logmsg () {
    logger "$1"
    echo "$1" > /dev/console
}

# this function is called when a fault is detected
# an error message can be passed
failure_handler () {
    logmsg "Health monitor detected a fault: $1"

    # some info useful for debugging
    logmsg "`ip addr`"
    logmsg "`uptime`"

    logmsg "Rebooting in 60 seconds"

    # avoid fast reboot cycles
    sleep 60

    logmsg "Rebooting now"
    reboot
}

# checks that an interface exists, expects the interface name as an argument
# the wifi interface is temporarily removed by the scripts so we must ensure
# that we ignore the temporary removal
# it is considered a failure, if the interface is found to be missing for 2 minutes
check_netif_exists () {
    for i in `seq 1 12`; do
        ip link show dev "$1" && return
        sleep 10
    done

    # if it gets here, it has been 2 minutes with the interface gone
    failure_handler "$1 interface does not exist"
}

# wait for 2 minutes to give the system a chance to start-up also
# it would avoid a fast reboot cycle in case there is a permanent failure
sleep 120

# check if this is a respawn by init
test -e /tmp/health_monitor_started && \
    failure_handler "the health monitor appears to have been restarted by init"
touch /tmp/health_monitor_started

logmsg "Software health monitor enabled"

# infinite health check loop
while true; do

    # check that the sdcts process exists
    pidof sdcts || failure_handler "sdcts process is not running"

    # check that the ppp0 interface exists
    check_netif_exists wlan0

    # check that the eth0 interface exists
    check_netif_exists eth0

    # do a health check every minute
    sleep 60
done
