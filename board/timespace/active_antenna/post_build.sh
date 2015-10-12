TARGETDIR=$1

echo "active antenna POST BUILD script: starting..."

regexp='s/^AC_INIT(\[sdcts\], \[\(.*\)\])[ \t]*$/\1/p'
ver=`sed -n -e "$regexp" ../../sdcts/configure.ac`
echo "Timespace Active Antenna $ver" > $TARGETDIR/etc/timespace-release

echo "active antenna POST BUILD script: done."
