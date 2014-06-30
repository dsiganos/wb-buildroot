#!/bin/ash
# /etc/dhcp/autoip.sh
# Extract last active lease info for matching ap-identifier not yet expired,
# and re-apply the lease settings.  Only re-apply minimal subset of options.
# jon.hefling@lairdtech.com


# iface
dev=$1

# mac
apmac=..:..:..:..:..:.. #$2

# ssid
apssid=$3

# bailout if not enabled...
grep -sq "^ENABLE_AUTOIP_REFRESH=yes" \
      /etc/dhcp/udhcpc.$dev.conf \
      /etc/dhcp/udhcpc.conf \
  || exit

#
# The 'apid' is a custom option:
#   option ap-identifier <mac> <ssid>
#
# This is inserted into the current lease info section for a wireless link.
#
test $# -lt 3 \
  && { echo $0: error; exit 2; }

# find lease-info section containing the apid and extract params
# w/ multiple hits, successive params will always win out anyway
if [ -s /var/lib/dhcp/dhclient.$dev.leases ]
then
  eval \
  $( sed -e '/^leas/,/}/{s/option//;H;$!d;}' \
         -e 'x;/ap-identifier'\ $apmac\ $apssid';/!d' \
          /tmp/dhclient.$dev.leases \
   \
    |sed -e '/expire/{s,/,-,g;s/expire[ 01-7]* \(.*\);/expire="\1";/p}' \
         -e 's/fixed-address \(.*\);/ip="\1";/p' \
         -e 's/subnet-mask \(.*\);/nm="\1";/p' \
         -e 's/broadcast-address \(.*\);/bc="\1";/p' \
         -e 's/routers \(.*\);/gw="\1";/p' \
         -n )
fi

# check if the lease is yet to expire before calling refresh
if [ -n "$expire" ] && expire=$( date --date="$expire" +%s )
then
  read -rs us is < /proc/uptime
  if [ ${us%.*} -lt $expire ]
  then
    interface=$dev \
    ip=$ip \
    subnet=$nm \
    broadcast=$bc \
    routers=$gw \
      /etc/dhcp/udhcpc.script refresh
  fi
fi

