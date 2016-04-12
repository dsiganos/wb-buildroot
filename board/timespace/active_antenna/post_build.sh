set -x

TARGETDIR=$1

echo "active antenna POST BUILD script: starting..."

regexp='s/^AC_INIT(\[sdcts\], \[\(.*\)\])[ \t]*$/\1/p'
ver=`sed -n -e "$regexp" ../../sdcts/configure.ac`
echo "Timespace Active Antenna $ver" > $TARGETDIR/etc/timespace-release

# remove the web server init scripts
rm -f $TARGETDIR/etc/init.d/S??lighttpd
rm -f $TARGETDIR/usr/sbin/lighty

# remove the inetd init script
rm -f $TARGETDIR/etc/init.d/S??inetd

# remove the bluetooth init script
rm -f $TARGETDIR/etc/init.d/S??bluetooth

# install scripts
cp board/timespace/active_antenna/health_monitor.sh $TARGETDIR/usr/sbin/
cp board/timespace/active_antenna/print_flash_hashes.sh $TARGETDIR/usr/sbin/

# create /sbin/wireless symlink
(cd $TARGETDIR/sbin && ln -sf /etc/network/wireless.sh wireless)

# create /var/dhcp symlink
ln -sfT ../../tmp $TARGETDIR/var/lib/dhcp

echo "active antenna POST BUILD script: done."
