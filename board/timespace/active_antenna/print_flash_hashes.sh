#!/bin/sh

# log a message on syslog and on the serial port
logmsg () {
    logger "$1"
    echo "$1" > /dev/console
}

bootstrap=`nice ionice -c 2 -n 7 md5sum /dev/mtdblock0 | cut -d ' ' -f 1`
uboot=`    nice ionice -c 2 -n 7 md5sum /dev/mtdblock1 | cut -d ' ' -f 1`
ubootenv=` nice ionice -c 2 -n 7 md5sum /dev/mtdblock2 | cut -d ' ' -f 1`
kernel=`   nice ionice -c 2 -n 7 md5sum /dev/mtdblock4 | cut -d ' ' -f 1`
rootfs=`   nice ionice -c 2 -n 7 md5sum /dev/mtdblock6 | cut -d ' ' -f 1`

logmsg "bootstrap: $bootstrap"
logmsg "uboot:     $uboot"
logmsg "ubootenv:  $ubootenv"
logmsg "kernel:    $kernel"
logmsg "rootfs:    $rootfs"
