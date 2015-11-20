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

echo "active antenna POST BUILD script: done."