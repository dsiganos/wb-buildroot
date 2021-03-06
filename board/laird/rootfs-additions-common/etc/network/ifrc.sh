#!/usr/bin/env ash
# /etc/network/ifrc.sh - interface_run_config
# A run-config/wrapper script to operate on kernel-resident network interfaces.
# Provides auto-reconfiguration via netlink up/down event support.
# Copyright (c) 2012 Jon Hefling
# ksjonh_20120520
#
usage() {
  rv=0
  [ "${1:0:5}" == "error" ] \
  && { echo -e "${2:+  $2\n}${3:+\nUsage:\n# $3\n}#"; rv=1; pause 2; }
  cat <<-	\
	usage-info-block
	$( echo -e "\t\t\t\t\t\t(interface-run-config v$ifrc_Version)\r \c"; \
	                                              ls -l $0 |grep -o "$0.*" )
	Configure and/or show network interfaces.
	Use settings in '/etc/network/interfaces', or from the command-line.
	Works with a netlink daemon to maintain dhcp/static methods on-the-fly.
	
	Flags:
	  -q   be quiet, no stdout
	  -v   be more verbose...
	  -n   no logging to files
	  -m   monitor ifrc events
	  -x   run w/o netlink daemon
	     ( Note:  ifrc may be disabled with:  /etc/default/ifrc.disable )
	  
	Interface:
	  name must be kernel-resident, or will try to start
	  can be an alias (such as 'wl' for wireless, see /e/n/i file)
	
	Action:
	  stop|start|restart   - act on phy-init/driver (up or down the hw-phy)
	  noauto|auto   - unset or set auto-starting an interface (for init/rcS)
	  address   - check an interface and report its ip-address, w/ exit code
	  status   - check an interface hw-phy status (if supported by phy-init)
	  up|dn   - up or down the interface configuration (re-'up' to renew)
	  logs   - list or manage related files: {clean|show [<iface>]}
	  eni   - edit file: /etc/network/interfaces
	  usage   - view file: /etc/network/networking.README
	
	Method:
	  dhcp [<param=value> ...]
	     - employ client to get/renew lease, info stored in leases file
	       requestip=x.x.x.x   - request an address (rip) from dhcp server
	       timeout=nn   - seconds to allow client to try/await response
	       ${mii_usage}\
	
	  static [ip=x.x.x.x[/b] <param=value> ...]
	     - use settings from /e/n/i file or those given on commandline
	       params:  address, netmask, broadcast, gateway  (ip,nm,bc,gw)
	
	  loopback [ip=x.x.x.x[/b]]
	     - use to set a specific localhost address
	
	  manual
	     - the interface will not be configured
	
	Usage:
	# ifrc [flags...] [<interface>] [<action>] [<method> [<param=value> ...]]
	#
	usage-info-block
  #
  exit $rv
}

# internals
ifrc_Version=20140612
ifrc_Disable=/etc/default/ifrc.disable
ifrc_Script=/etc/network/ifrc.sh
ifrc_Lfp=/tmp/ifrc
ifrc_Cmd=$0\ $@
ifrc_Pid=$$
ifrc_Via=''
ifrc_Log=${ifrc_Lfp}/msg

# latch settings
eval $ifrc_Settings

# ensure ifrc exists and is supported as a system executable
ifrc=/sbin/ifrc
[ -x "$ifrc" ] || ln -sf $ifrc_Script $ifrc
[ ${#ifrc_Lfp} -gt 5 ] || ifrc_Lfp=/tmp/ifrc
[ -d "$ifrc_Lfp" ] || mkdir -p ${ifrc_Lfp}

# check network-init-script
test -x ${nis:=/etc/init.d/S??network} \
  || nis="echo Cant exec: ${nis:-network-init-script}"

# ensure /e/n/i exists...
test -s ${eni:=/etc/network/interfaces} \
  || { test -s $eni~ && mv -f $eni~ $eni; } \
  || { rm -f $eni~ && gzip -fdc $eni~.gz >$eni; } \
  || { printf "# $eni - ifrc\n\nauto lo\niface lo inet loopback\n\n\n" >$eni; }

# check mii (optional)
mii=/usr/sbin/mii-diag
if [ ! -x "$mii" ]
then
  mii=
else
  # this package is used to optionally set a fixed port speed during dhcp
  mii_usage="portspeed=10baseT...   - use a fixed speed during dhcp trial"$'\n'
fi

# check resolv.conf configurator (optional
test -x ${conf_resolv:=/usr/sbin/conf-resolv} \
  || conf_resolv=:\ $conf_resolv
$conf_resolv -c

msg() {
  if [ "$1" == "@." ] && shift
  then
    # w/'@.' prefix
    if [ -n "$mm" ]
    then
      # to controlling pty in monitor-mode
      echo "$@" >$mm 2>/dev/null || mm=
      # and to syslog if verbose too
      test -n "$vm" \
        && logger -tifrc \
            "$IFRC_STATUS $IFRC_DEVICE ${IFRC_ACTION:-??} m:${IFRC_METHOD%% *}"
      return
    fi
  else
    # to stdout while not quiet-mode
    [ -z "$qm" ] && echo "$@" || :
  fi
  # and log to file unless set to /dev/null
  echo "$@" >>${ifrc_Log:-/dev/null} || :
}

parse_flag() {
  case $1 in
    -h|--help|--usage) ## show usage
      usage $2
      ;;
    --|--version) ## just report version
      echo ifrc -- v$ifrc_Version - md5:`md5sum < $0` len:`wc -c < $0`; exit 0
      ;;
    -q) ## quiet, no stdout
      qm='>/dev/null'
      ;;
    -v) ## add verbosity, multi-level
      vm=$vm.
      ;;
    -n) ## do not use a log file
      ifrc_Log=/dev/null
      ;;
    -m*) ## monitor nl/ifrc events for iface
      test -z "${mm:=${1:2}}" && { mm=`tty` || mm=/dev/console; }; true
      ;;
    -x) ## do not run netlink daemon
      ifnl_disable=.
      ;;
    -*) ## ignore
      msg \ \ ...ignoring: \[$1\]; return 0
      ;;
    *) ## break
      return 1
  esac \
    && fls=${fls:+$fls }$1
}
while :; do parse_flag $1 && shift || break; done

# set some message levels according to verbose-mode
[ -n "${vm:2:1}" ] && alias msg3=msg || alias msg3=:                           
[ -n "${vm:1:1}" ] && alias msg2=msg || alias msg2=:                           
[ -n "${vm:0:1}" ] && alias msg1=msg || alias msg1=:                           
[ -z "${qm:0:1}" ] && alias msg0=msg || alias msg0=:

# don't run ifrc if the 'disable' flag-file exists
[ -f "$ifrc_Disable" ] && { msg1 "  $ifrc_Disable exists..."; exit 0; }

# netlink support
ifnl=ifplugd

# set ifnl_s when called via netlink daemon
ifnl_s=${IFPLUGD_PREVIOUS}-\>${IFPLUGD_CURRENT}
ifnl_s=${ifnl_s//error/er}
ifnl_s=${ifnl_s//down/dn}
ifnl_s=${ifnl_s//dormant/dt}
[ "$ifnl_s" == "->" ] && ifnl_s=

[ -n "$rcS_" ] && ifrc_Via="-- ${PPID}_rcS"
[ -n "$ifnl_s" ] && ifrc_Via="-- ${PPID}_$ifnl"
[ -n "$ifrc_Via" ] && qm='>/dev/null'

[ "$vm" == "....." ] && set -x

pause() { 
  # n[.nnn] sec -- a zero value means indefinite
  test -p ${ifrc_Lfp}/- || mkfifo ${ifrc_Lfp}/- 2>/dev/null
  read -rst${1:-1} <>${ifrc_Lfp}/- 2>/dev/null
  if test $? -eq 2
  then
    s="${1/.*}"
    us="000000"
    [ -z "${1/*.*}" ] && us="${1/*.}$us"
    usleep $s${us:0:6}
  fi
  return 0
}

gipa() {
  ip=`ip addr show $1 2>/dev/null \
     |grep -o '[0-9]*\.[0-9]*\.[0-9]*\.[0-9/]* *'` && echo ${ip%% *}
}

sleuth_wl() {
  # try to find kernel-resident (wireless) interface: wl
  # in this case, it is not certain what the name is ahead of time
  for x in /sys/class/net/*/phy80211
  do
    x=${x##*net/}; x=${x%%/*}; [ "$x" != \* ] && { echo $x; break; }
  done
}

summarize_interface_status() {
  if ! grep -qs 'u[pn]' /sys/class/net/$dev/operstate
  then
    is=inactive
  else
    is=active
    { read -r x </sys/class/net/$dev/carrier; } 2>/dev/null
    if ! let x+0
    then
      is="$is, no_carrier/cable/link"
    else
      [ ! -d /sys/class/net/$dev/phy80211 ] \
      && is="$is, linked" \
      || { iw dev $dev link |grep -q Connected && is="$is, associated"; } \
    fi
  fi
  ps ax |grep -q "ifplug[d].*${dev}" && is="...managed, $is" || is="...$is" 
}

show_interface_config_and_status() {
  # find available iface's not configured
  # these will exist, and be in down state
  ida=$( grep -s down /sys/class/net/*/operstate \
        |sed 's/.*net\/\(.*[^/]\)\/.*/ \1/' \
        |tr -d '\n' )

  [ -z "$dev" -a -n "$ida" ] \
  && echo "       Available, but not configured: $ida"

  [ -n "${vm:1:1}" ] \
  && filter=';s/ mtu/\n\t&/;s/\( state [^ ]*\)\(.*\)/\2\1/' \
  || filter=';s/ qdisc//;s/ pfi[^ ]*//;s/ qlen [0-9]\+//'

  ip addr show ${dev:+dev $dev} \
    |sed -e 's/^[0-9]\+: //;s/\([a-z].*:\) /\n\1\t/'"$filter"';s/    /\t/' \
         -e '/inet6/d;/valid_lft/d'

  : ${dev:=$( sleuth_wl )}
  # include association info for wireless dev
  if [ -d /sys/class/net/$dev/phy80211 ]
  then
    echo -e "\nWiFi:\t`sed 's/up/active/' /sys/class/net/$dev/operstate`"
    iw dev $dev link 2>/dev/null \
      |sed 's/^Connec/Associa/;s/t connec.*/t associated (on '$dev')/' \
      |sed '/[RT]X:/d;/^$/,$d;s/^\t/        /'
  fi
  return 0
}

ifrc_stop_netlink_daemon() {
  prg="${ifnl##*/}"
  # find daemon instances for this interface
  for pid in \
  $( ps ax |sed -n "/${dev}/s/^[ ]*\([0-9]*\).*[\/ ]\(${prg}\) -.*/\1_\2 /p" )
  do
    kill ${pid%%_*} && msg1 "  $pid <- sigterm:0"
  done
}

signal_dhcp_client() {
  case $1 in
    RELEASE) action=sigusr2; signal=-12;;
    RENEW) action=sigusr1; signal=-10;;
    TERM) action=sigterm; signal=-15;;
    CHECK) action=sigzero; signal=-00;;
  esac
  rv=1
  if { read -r pid < /var/run/dhclient.$dev.pid; } 2>/dev/null \
  && { read client < /proc/$pid/comm; } 2>/dev/null
  then
    kill $signal $pid
    rv=$?
    msg1 "  ${pid}_$client <- $action:$rv"
    if [ "$1" == "TERM" ]
    then
      x=16
      while [ -d /proc/$pid ] && pause 0.333
      do
        let --x \
        || { msg "  ${pid}_$x <- $action error"; rv=1; break; }
      done
    fi
  fi

  # interrupt link-beat check, while if in-progress
  rmdir ${ifrc_Lfp}/$dev.lbto 2>/dev/null
  return $rv
}

make_dhcp_renew_request() {
  for x in 1 2 3 4 5
  do
    { read -r txp_b </sys/class/net/$dev/statistics/tx_packets; } 2>/dev/null
    signal_dhcp_client RENEW || break
    pause 1
    { read -r txp_a </sys/class/net/$dev/statistics/tx_packets; } 2>/dev/null

    msg2 "    tx_packets: $txp_b -> $txp_a"
    let txp_b=$txp_a-$txp_b && return 0
  done
  msg1 "    failed $x attempts"
  return 1
}

# 
# the 1st arg should be an interface dev name
# however, some actionable exceptions can be handled before qualifing iface dev
case $1 in

  stop|start|restart) ## call network-init-script w/action-&-method, no return
    ifrc_stop_netlink_daemon
    [ -n "${vm:0:1}" ] && set -x
    exec $nis $1 $2
    ;;

  log|logs) ## ifrc files
    f=${3/[a-z][a-z]*/-}
    if [ "${2:0:4}" == "show" -a "$f" == - ] 
    then
      less -Em~ ${ifrc_Lfp}/$3 2>/dev/null
    elif [ "${2:0:4}" == "clea" -a "$f" == - ]
    then
      for f in ${ifrc_Lfp}/${3:-*}*; do
        rm $f 2>/dev/null && let ++c && echo -n ${f##*/}' '
      done
      let c && echo ...removed from $ifrc_Lfp
    else
      for x in $ifrc_Lfp/*; do [ -f $x ] && printf "% 8d %s\n" `wc -c $x`; done
    fi
    exit $?
    ;;

  show|"") ## iface missing, and no other action, so show any/all
    echo "Configuration for all interfaces" \
         "                          (try -h to see usage)"
    if show_interface_config_and_status 
    then
      echo
      /etc/network/bridge.sh 2>/dev/null && echo
      echo Routing:
      ip route show
      echo -e "\nDNS:\r\tresolv.conf"
      sed '/^#/d;/^$/d' /etc/resolv.conf 2>/dev/null
    fi
    exit 0
    ;;

  usage) ## view the readme file
    less -Em~ /etc/network/networking.README
    # NOTE - the EOF detect/quit is not working in bb_1.19.3 - bb_1.21.x
    exit $?
    ;;

  eni) ## edit the /e/n/i file
    cp -f $eni ${ifrc_Lfp}/${eni##*/}~
    if vi ${ifrc_Lfp}/${eni##*/}~ -c /^${2:+"iface $2.*"}$ \
    && ! cmp -s ${ifrc_Lfp}/${eni##*/}~ $eni
    then
      [ -s ${ifrc_Lfp}/${eni##*/}~ ] \
      && mv -f ${ifrc_Lfp}/${eni##*/}~ $eni \
      || echo "unable to copy edited $eni into place"
    fi
    exit $?
    ;;  

  noauto|auto) ## report 'auto <iface>'s
    echo $1 interfaces: `sed -n "/^${1/no/#} [a-z]/s/^.* / /p" $eni |tr -d '\n'`
    echo "  ...usage: ${0##*/} <iface> {noauto|auto}"
    exit 0
    ;;

  flags|address|status|down|dn|up) ## require iface
    usage error: "...must specify an interface" "ifrc <iface> $1" 
    ;;

  [a-z][a-z]*) ## accept an <iface> dev name starting with two letters
    dev=$1 && shift
    ;;

  *) usage error: "...invalid interface name";;
esac

read_ifrc_info() {
  if [ -f $ifrc_Lfp/$1 ] \
  && exec 3< $ifrc_Lfp/$1
  then
    x= # method-&-params, and cdt{ *cfg-do tasks ;}
    read -rs x <&3 \
      && [ "${x/mp_cdt:*/mp_cdt}" == mp_cdt ] \
      && mp_cdt=${x#*:}

    x= # crc32 of the iface stanza from /e/n/i file
    read -rs x <&3 \
      && [ "${x/eni_sk:*/eni_sk}" == eni_sk ] \
      && eni_sk=${x#*:}

    x= # iface rc info as alias=iface and any flags
    read -rs x <&3 \
      && [ "${x/ifrc_i:*/ifrc_i}" == ifrc_i ] \
      && ifrc_i=${x#*:}

    if [ -n "$ifrc_i" ]
    then
      #:alias=iface & settings
      ifrc_Settings=${ifrc_i#* }
      ifrc_i=${ifrc_i% $ifrc_Settings}
      devalias=${ifrc_i%=*}
      dev=${ifrc_i#*=}
    fi
    exec 3<&-
    if [ -n "$devalias" ]\
    && [ -n "$dev" ]
    then
      return 0
    fi
  fi
  return 1
}

if ! read_ifrc_info $dev \
|| [ -z "$mp_cdt" ]
then
  # Generally, operations are on a specific interface.
  # It is possible that the $dev may initially be unknown.
  # So, for /e/n/i file lookups, we assume the use of $devalias.
  #
  # Find iface stanza using '$dev' as a dev*alias or as dev*iface name.
  # Then extract any general settings for it.
  msg3 "  checking /e/n/i file..."
  D='[a-z][a-z][a-z0-9]*'
  devalias=$( sed -n "/$dev/s/^[ \t]*alias \($D\)[ is]* \($D\)/\1 \2/p" $eni )
  if [ -n "$devalias" ]
  then
    if grep -q "^iface ${devalias%% *} inet" $eni
    then # matched dev*alias name via alias
      ifacemsg="${devalias%% *} (alias)"
      dev=${devalias##* }
      devalias=${devalias%% *}
    elif grep -q "^iface ${devalias##* } inet" $eni
    then # matched dev*iface name via alias
      ifacemsg="${devalias%% *} (alias)"
      dev=${devalias##* }
      devalias=${devalias##* }
    fi
  elif grep -q "^iface $dev inet" $eni
  then # matched name via dev
    ifacemsg="$dev"
    devalias=$dev
  fi
  # dev*alias is used to further process settings for dev*iface in /e/n/i
  msg3 "  iface stanza: ${ifacemsg:-?}"
  test -n "$devalias" \
    || exit 1

  # re-attempt lookup
  read_ifrc_info $dev

  # read ifrc-flags if not more than '-v' specified on cli - cummulative
  test -z "${fls//-v/}" \
    && fls=${fls//-v/} \
    && flags_eni=$( sed -n "/^iface $devalias/,/^$/\
                      s/^[ \t]\+[^#]ifrc-flags \(.*\)/\1/p" $eni )

  # apply flags from iface stanza in /e/n/i
  for af in $flags_eni; do parse_flag $af || break; done
fi
msg3 "  deviface: ${dev:-?}"
test -n "$dev" \
  || { msg "iface?"; exit 1; }

# check if this is a wireless interface
test -d /sys/class/net/$dev/phy80211 && phy80211=true || phy80211=false

# Set logfile name for this iface.
ifrc_Log=${dev:+${ifrc_Lfp}/$dev}
{ read -rs us is < /proc/uptime; } 2>/dev/null

# A tmp file per iface is used for run-config and logging event/state/actions.
# Reserved lines are:
# 1.'mp_cdt' method-&-params, *cfg-do tasks -{ when run-config status is 'up' }
# 2.'eni_sk' stanza cksum from /e/n/i -{ when differs then not a re-'up' }
# 3.'ifrc_i' interface run-config info
#
# Each successive <iface> event-state-action is time stamped.
# Limit the file size to about 100-blocks, by snipping twenty lines
# of content within the log, and while retaining twenty line header.
{ test 0`wc -c < $ifrc_Log` -le 102400 \
    || sed '21,41d;42i<snip>' -i $ifrc_Log; } 2>/dev/null

test ! -f $ifrc_Log \
  && x="\n\n\n     -- v$ifrc_Version - md5:`md5sum < $0`" || x=

printf "${x%  -}\n% 13.2f __${ifrc_Cmd}  $ifrc_Via\n" $us >>$ifrc_Log
msg3 -e "env:\n`env |sed -n 's/^IF[A-Z]*_.*/  &/p' |grep . || echo \ \ ...`\n"

make_() { ( eval $1; x=$?; [ ${1:0:1} == / ] && echo \ \ ${1##*/}: $x ); }

fn() { { msg2 "+ $*"; } 2>/dev/null; eval "$*" 2>&1 || { msg "? $*"; false; }; }

export ifrc_Settings=fls=\"$fls\"\ mm=$mm\ vm=$vm\ qm=$qm

# external globals - carried per instance and can be used by *-do scripts
export IFRC_STATUS="${ifnl_s:-  ->  }"
export IFRC_DEVICE=$dev
export IFRC_ACTION
export IFRC_METHOD
#export IFRC_SCRIPT

# determine action to apply - assume 'show'
test -n "$1" \
  && { IFRC_ACTION=$1; shift; } \
  || { [ -z $ifnl_disable ] && IFRC_ACTION=show; }

# Determine method and params and tasks to apply.
if [ "$IFRC_ACTION" == "up" ]
then
  # get current iface stanza crc from /e/n/i
  eni_sc=$( sed '/./{H;$!d;};x;/[#]*iface '$devalias' inet/!d;n' $eni |cksum )

  if [ -n "$ifnl_s" ]
  then
    # a re-'up' called by ifnl
    methvia="(ifnl: $dev.cfg)"
    IFRC_METHOD=${mp_cdt%% cdt{*}
    IFRC_SCRIPT=${mp_cdt/*cdt{/{}
  else
    if [ -n "$1" ]
    then
      # remaining args: method-&-params, cdt{ *cfg-do's
      methvia="(set via cli)"
      IFRC_METHOD=${@%% cdt{*}
      IFRC_SCRIPT=${@##* cdt{}
    else
      # a re-'up' when iface stanza not changed in eni
      if [ -n "$mp_cdt" -a -z "${eni_sc/$eni_sk}" ]
      then
        # use cfg in lieu of change
        methvia="(via $dev.cfg)"
        IFRC_METHOD=${mp_cdt%% cdt{*}
        IFRC_SCRIPT=${mp_cdt/*cdt{/{}
      else
        # use eni settings
        methvia="(via /e/n/i)"
        IFRC_METHOD=$( sed -n "/^iface $devalias inet /\
                              {s/.* inet \([a-z]*\)/\1/p;q;}" $eni )
        set -- $IFRC_METHOD \
               $( sed -n "/^iface $devalias inet $IFRC_METHOD/,/^if/!d;/^$/q;\
                              s/^[ \t]\+\([^#][a-z]*\)[ ]\(.*\)/\1=\2/p" $eni )
        IFRC_METHOD=$@
      fi
    fi

    # check /e/n/i for ifrc-pre/post-d/cfg-do tasks
    # only do this if not already set and not via nld
    if [ -z "$IFRC_SCRIPT" -a -z "$ifnl_s" ]
    then
      msg3 "parsing /e/n/i for pre/post conf directives, intended for $dev..."

      set -- "$( sed -n "/^iface $devalias/,/^if/!d;/^$/q;\
         s/^[ \t]\+\([^#]p[or][se][t]*\)-\([d]*cfg\)-do \(.*\)/\1_\2_do='\3'/p"\
                       $eni 2>/dev/null )"
      IFRC_SCRIPT=$@
    fi
  fi
  shift $#

  # assume method if none
  if [ -z "$IFRC_METHOD" ]
  then
    methvia="(assumed)"
    IFRC_METHOD="dhcp"
  fi
  IFRC_SCRIPT=${IFRC_SCRIPT/$IFRC_METHOD}
elif \
   [ "$IFRC_ACTION" == "dn" ] \
|| [ "$IFRC_ACTION" == "down" ]
then
  if [ "${mp_cdt/*cdt{*/cdt}" == "cdt" ]
  then
    IFRC_SCRIPT=${mp_cdt/*cdt{/{}
  fi
fi
eval $IFRC_SCRIPT \
  || msg "**cfg-do-task error - $IFRC_SCRIPT"

# Determine netlink event rule to apply via the reported iface status.
# The action may be overridden depending on the following event rules.
if [ -n "$ifnl_s" ]
then
  ## run via nl daemon, consume extra args
  shift $#

  ## nl event rules for status '  ->dn'
  while [ "${IFRC_STATUS##*->}" == "dn" ]
  do
    ## handle a temporarily lost interface
    if [ ! -f /sys/class/net/$dev/carrier ]
    then
      msg1 $dev is gone, waiting 2s
      pause 2
      if [ ! -f /sys/class/net/$dev/carrier ]
      then
        msg1 $dev is gone, allowing deconfigure
      else
        msg1 ignoring dn event - iface is back
        IFRC_ACTION=xx
      fi
      break
    fi

    ## maybe signal client to release
    if [ "${IFRC_METHOD%% *}" == "dhcp" ]
    then
      if [ ! -d ${ifrc_Lfp}/$dev.dhcp ]
      then
        signal_dhcp_client RELEASE
        IFRC_ACTION=xx
      else
        msg1 "dhcp client lock exists, no act"
        IFRC_ACTION=xx
      fi
      break
    fi

    ## by default the ip-cfg is not retained on a down event
    ip addr flush dev $dev 2>/dev/null

    ## otherwise ignore down event via ifnl - no deconfigure
    IFRC_ACTION=xx
    break
  done

  ## nl event rules for status '  ->up'
  while [ "${IFRC_STATUS##*->}" == "up" ]
  do
    ## maybe signal client to renew
    if [ "${IFRC_METHOD%% *}" == "dhcp" ]
    then
      if [ ! -d ${ifrc_Lfp}/$dev.dhcp ]
      then
        : signal_dhcp_client RENEW
      else
        : msg1 "dhcp client lock exists, no act"
        : IFRC_ACTION=xx
      fi
      break
    fi
    break
  done

  msg @. ifrc_s/d/a/m: "$IFRC_STATUS" $IFRC_DEVICE ${IFRC_ACTION:---} \
                       ${IFRC_METHOD%% *} #cdt"${IFRC_SCRIPT:-{\}}"
else
  # rt_tables support...
  if ip rule >/dev/null 2>&1 \
  && [ -f /etc/iproute2/rt_tables ] \
  && { read i < /sys/class/net/$dev/ifindex; } 2>/dev/null
  then
    let i+=100; tn=t.$dev
    grep -q "$tn" /etc/iproute2/rt_tables \
      || printf "$i\t$tn\n" >>/etc/iproute2/rt_tables
  fi
fi

#
# The hw-phy/init scripts are responsible for creating/removing an iface.
# This script uses down/up with respect to interface (de)configuration only!
#
case $IFRC_ACTION in
  address) ## check if iface is configured and show its ip-address
    # affirm configured <iface>: ip-address [...status]:0/1
    # returns true if the iface is configured with an ip-address
    is=; ip=$( gipa $dev ); rv=$?
    [ -n "${vm:0:1}" ] && { ip=${ip:-0.0.0.0}; summarize_interface_status; }
    [ -n "$ip$is" ] && msg $ip $is
    exit $rv
    ;;

  status) ## call on phy-init for status, no return
    [ -n "${vm:0:1}" ] && set -x
    exec $nis $devalias $IFRC_ACTION ${IFRC_METHOD%% *}
    ;;

  show) ## show info/status for an iface
    test -f /sys/class/net/$dev/uevent \
    || { echo \ \ ...not available, not a kernel-resident interface; exit 1; }
    summarize_interface_status
    echo Configuration for interface: $ifacemsg $is
    if grep -qs Generic /sys/class/net/$dev/*/uevent
    then
      echo Warning: using 'Generic PHY' driver
      [ -n "$mii" ] && $mii $dev |sed -n '/Yo/,$d;/media type/,$p'
    fi
    show_interface_config_and_status
    if [ "${dev:0:2}" == "br" ]
    then
      echo
      /etc/network/bridge.sh 2>/dev/null
    else
      if [ "$dev" == "lo" ]
      then
        echo -e "\nRouting: (local)"
        ip route show table local dev $dev \
        |sed 's/^/  /;s/broad/b/;s/  pr/\t pr/'
      else
        echo -e "\nRouting: "
        ip route show dev $dev
        echo -e "\nARP:     \n  ...\c"
        ip neigh show dev $dev \
          |sed '1s/^./\r&/;s/lladdr/at/'
      fi
    fi
    if [ -n "${vm:0}" ] && gipa $dev >/dev/null
    then
      f1='\(....\)'
      f2='\(:[^ ]* *[^ ]*:[^ ]* *\)'
      f3='\(\".*\",[0-9]*\)'
      echo -e "\nConnections:\n  ...\c"
      ss -4ntuwp \
        |sed -e '1{s/.*//;N;s/\n//};/user/!d' \
             -e 's/^'"$f1"'.*'"$f2"'u[^ ]\+'"$f3"',.*/\r\1   \2   \3/'
    fi
    if [ -n "${vm:0}" ]
    then
      echo -e "\nProcesses:"
      ps ax -opid,stat,args |grep "[ .iI]$dev[ .]" || echo \ \ ...
    fi
    echo
    exit 0
    ;;

  flags) ## (re)set ifrc-flags for an iface
    msg "not implemented"
    exit 0
    ;;

  eni) ## report interface stanza
    sed '/./{H;$!d;};x;/[#]*iface '$devalias' inet/!d;n' $eni
    exit 0
    ;;

  noauto|auto) ## unset or set auto-starting an interface
    auto=${IFRC_ACTION/no/#}
    if grep -q "auto $devalias$" $eni
    then
      ## edit the #auto|auto iface, for the interface stanza
      sed "/^[#]*auto $devalias$/s/^.*/$auto $devalias/" $eni >$eni~
    else
      if grep -q "^iface $devalias inet" $eni
      then
        ## insert a #auto|auto iface, for the interface stanza
        sed "/^iface $devalias inet/i$auto $devalias" $eni >$eni~
      else
        echo "$devalias stanza not found in $eni"
        exit 1
      fi
    fi
    [ -s $eni~ ] && mv -f $eni~ $eni
    exit $?
    ;;

  stop|start|restart) ## act on phy-init/driver, does not return
    ifrc_stop_netlink_daemon
    [ -n "${vm:0:1}" ] && set -x
    exec $nis $devalias $IFRC_ACTION ${IFRC_METHOD%% *}
    ;;

  dn|down) ## assume down action ->deconfigure
    ##
    if [ -n "$pre_dcfg_do" ]
    then
      msg1 -E "  pre-dcfg-do( $pre_dcfg_do )"
      make_ "$pre_dcfg_do" |tee -a $ifrc_Log & pre_dcfg_do=
    fi
    sed '1cmp_cdt:' -i $ifrc_Log
    msg1 "deconfiguring $dev"
    #
    # terminate any other netlink/dhcp_client daemons and de-configure
    ifrc_stop_netlink_daemon 
    signal_dhcp_client TERM
    # remove all relative entries from the routing table
    # the iface is still up and accessible to the IP layer
    fn ip addr flush dev $dev
    # also remove any applicable policy rules for the iface
    while ip rule del not table $tn 2>/dev/null; do :;done
    ##
    if [ -n "$post_dcfg_do" ]
    then
      msg1 -E "  post-dcfg-do( $post_dcfg_do )"
      make_ "$post_dcfg_do" |tee -a $ifrc_Log & post_dcfg_do=
    fi
    rmdir ${ifrc_Lfp}/$dev.* 2>/dev/null
    exit 0
    ;;

  up) ## assume up action ->reconfigure
    if [ ! -f /sys/class/net/$dev/uevent ]
    then
      # interface does not exist yet, must start
      if mkdir ${ifrc_Lfp}/$dev.nis 2>/dev/null
      then
        sed '1cmp_cdt:' -i $ifrc_Log
        unset IFRC_SCRIPT IFRC_STATUS
        msg "interface is not kernel-resident, trying to start ..."
        [ -n "${vm:0:1}" ] && set -x
        exec $nis $devalias start ${IFRC_METHOD%% *}
      else
        msg "interface is not kernel-resident, try:  ifrc $dev start"
        exit 1
      fi
    fi
    rmdir ${ifrc_Lfp}/$dev.nis 2>/dev/null

    test "${methvia/*cfg*/cfg}" == "cfg" && re=re- || re=
    msg1 "${re}configuring $dev using ${IFRC_METHOD%% *} method ${methvia:-(?)}"
    mkdir ${ifrc_Lfp}/$dev.cfg 2>/dev/null \
      || { msg1 "  ...$dev.cfg already in progress"; exit 0; }

    if [ ! -n "$re" ]
    then
      ## new conf 'up' method
      mp_cdt=
      sed -e "1cmp_cdt:$mp_cdt" \
          -e "2ceni_sk:$eni_sc" \
          -e "3cifrc_i:$devalias=$dev $ifrc_Settings" \
          -i $ifrc_Log

      if [ "$dev" != "lo" ] && [ "$devalias" != "wl" ] && ! $phy80211
      then
        # ethernet wired phy-hw is external; so try to determine if really there
        # the generic phy driver is present when phy-hw is otherwise unsupported
        if grep -s Generic /sys/class/net/$dev/*/uevent >/dev/stderr
        then
          msg "Warning: unknown '$dev' iface-phy-hw ...using generic phy driver"
          [ -z "$mii" ] && exit 1 || $mii $dev |grep -B12 fault && exit 2
        fi
      fi
      test -z "$ifnl_s" \
        && ifrc_stop_netlink_daemon

      signal_dhcp_client TERM
      fn ip addr flush dev $dev
      fn ip link set dev $dev up
      ## the interface is now de-configured (flush) and also re-'up'd
      ## additional wait time may be required to be ready again
      ## operations continue below...
      #pause 0.333
    fi
    ;;

  \.\.) ## refresh cached configuration
    eni_sc=$( sed '/./{H;$!d;};x;/[#]*iface '$devalias' inet/!d;n' $eni |cksum )
    if [ -d ${ifrc_Lfp}/$dev.cfg ]
    then
      msg1 \ \ ...$dev.cfg exists, no refresh
    else
      sed -e "2ceni_sk:$eni_sc" \
          -e "3cifrc_i:$devalias=$dev $ifrc_Settings" \
          -i $ifrc_Log
    fi
    exit 0
    ;;

  '') ## no action unless disable nl for interface
    [ -n "$ifnl_disable" ] && ifrc_stop_netlink_daemon
    exit 0
    ;;

  er|dt|xx|\.*) ## no action
    msg2 \ \ ...no action on $dev
    exit 0
    ;;

  *) ## usage, does not return
    usage error: "...invalid action specified"
    ;;
esac

#
# The rest of this script handles the configuration of an interface.
# And is run when called again manually, or via the netlink daemon.
#
# Firstly, ensure that the netlink daemon is active for <interface>.
# Exceptions:
[ "${IFRC_METHOD%% *}" == "manual" ] && ifnl_disable=.
[ "$dev" == "lo" ] && ifnl_disable=.

if [ -n "$ifnl_disable" ]
then
  ifrc_stop_netlink_daemon
else
  mkdir ${ifrc_Lfp}/$dev.nld 2>/dev/null \
    || { msg1 "$ifnl start, ...already in progress"; exit 0; }

  if ! { ps ax |grep -q "$ifnl[ ].*${dev}" && msg2 "  $ifnl is running"; }
  then
    # when not verbose, don't log to syslog
    [ -z "${vm:0:1}" ] && nsl=-s || nsl=   
    #
    # allow auto API mode for all interfaces except wireless
    $phy80211 && api=-miff
    #
    # start the netlink daemon
    $ifnl -i$dev $api $nsl -fa -qMp -u0 -d0 -Ir$0

    msg1 "  $ifnl started"
  fi
fi
rmdir ${ifrc_Lfp}/$dev.nld 2>/dev/null

#
# This script will exit with a zero value, even if configuration is deferred,
# which is considered a valid state.  A link UP event captured by the netlink
# daemon, will cause configuration to be re-attempted for:
# 1. wifi is not associated yet (handled by supplicant)
# 2. cable/link not present yet
#
# The script will exit with a non-zero value whenever a permanent condition
# prevents configuration of the interface, such as:
# 1. invalid method specified
# 2. no hw-phy detectable
# 3. timeout was used
# 4. other errors
#

rc_exit() {
  rmdir ${ifrc_Lfp}/$dev.cfg 2>/dev/null
  exit $1
}

show_filtered_method_params() {
  if [ "${methvia/*cfg*/cfg}" != "cfg" ]
  then
    if [ -n "$vm" ]
    then
      if [ -n "$ip$nm$gw$bc$ns" ]
      then
        echo \ \ ip: $ip
        echo \ \ nm: $nm
        echo \ \ gw: $gw
        echo \ \ bc: $bc
        echo \ \ ns: $ns
      fi
      [ -n "$rip" ] && msg request-ip-address: $rip
      [ -n "$client" ] && msg dhcp client: $client
      [ -n "$metric" ] && msg metric is: $metric
    fi

    if [ -n "$IFRC_SCRIPT" ]
    then
      # strip newlines and expand other escapes for sed
      IFRC_SCRIPT=${IFRC_SCRIPT//$'\n'/}
      IFRC_SCRIPT=${IFRC_SCRIPT//\\/\\\\}
      set -- "$mp_cdt cdt{$IFRC_SCRIPT\; }"
    else
      set -- "$mp_cdt"
    fi
    sed "1cmp_cdt:$@" -i $ifrc_Log
  fi
}

cidr_to_ip_nm() {
  if ip=${1%/*} && [ ${1%/[0-9]*} != ${1} ]
  then
    local px maskpat=255\ 255\ 255\ 255
    local mx maskdgt=254\ 252\ 248\ 240\ 224\ 192\ 128
    let px=${1#*/}/8 px*=4 mx=7-${1#*/}%8 mx*=4
    set -- ${maskpat:0:$px}${maskdgt:$mx:3}
    nm=${1:-0}.${2:-0}.${3:-0}.${4:-0}
    unset px maskpat mx maskdgt
  fi
}

ifrc_validate_loopback_method_params() {
  for x in $IFRC_METHOD
  do
    case ${x%%=*} in
      loopback)
        ;;
      ip|address)
        ip=${x##*=}
        ;;
      *)
        msg3 "ignoring extra parameter: [$x]"
        continue
    esac
    mp_cdt=${mp_cdt:+$mp_cdt }$x
  done
  show_filtered_method_params
}

ifrc_validate_static_method_params() {
  for x in $IFRC_METHOD
  do
    case ${x%%=*} in
      static)
        ;;
      ip|address)
        cidr_to_ip_nm ${x##*=}
        ;;
      nm|netmask)
        nm=${x##*=}
        ;;
      gw|gateway)
        gw=${gw:+$gw }${x##*=}
        ;;
      bc|broadcast)
        bc=${x##*=}
        ;;
      ns|nameserver)
        ns=${ns:+$ns }${x##*=}
        ;;
      metric)
        metric=${x##*=}
        ;;
      weight)
        weight=${x##*=}
        ;;
      fpsd|portspeed)
        fpsd=${x##*=}
        ;;
      *)
        msg3 "ignoring extra parameter: [$x]"
        continue
    esac
    mp_cdt=${mp_cdt:+$mp_cdt }$x
  done
  show_filtered_method_params
}

ifrc_validate_dhcp_method_params() {
  for x in $IFRC_METHOD
  do
    case ${x%%=*} in
      dhcp) ## method
        ;;
      rip|requestip) ## specify ip to request from server (if supported)
        rip=${x##*=}
        ;;
      metric) ## apply a hop metric for default router
        metric=${x##*=}
        ;;
      weight) ## apply a nexthop weight for router
        weight=${x##*=}
        ;;
      fpsd|portspeed) ## specify a fixed-port-speed-duplex
        fpsd=${x##*=}
        ;;
      to|timeout) ## specify a minimum timeout of 4s
        to=${x##*=}; [ 4 -le $to ] || let to=4
        ;;
      client) ## specify a preferred client
        client=${x##*=}
        ;;
      *)
        msg3 "ignoring extra parameter: [$x]"
        continue
    esac
    mp_cdt=${mp_cdt:+$mp_cdt }$x
  done
  show_filtered_method_params
}

ifrc_validate_manual_method_params() {
  for x in $IFRC_METHOD
  do
    case ${x%%=*} in
      manual) ## method
        ;;
      *)
        msg3 "ignoring extra parameter: [$x]"
        continue
    esac
    mp_cdt=${mp_cdt:+$mp_cdt }$x
  done
  show_filtered_method_params
}

check_link() {
  test -n "$ifnl_s" && return
  mkdir ${ifrc_Lfp}/$dev.lbto

  # await link-beat-time-out of 4s or 20s
  $phy80211 && lbto=4000 || lbto=20000
  let n=0
  while [ $n -lt $lbto -a -d ${ifrc_Lfp}/$dev.lbto ]
  do
    if $phy80211
    then
      grep -qs up /sys/class/net/${dev}/operstate && break
    else
      grep -qs 1 /sys/class/net/${dev}/carrier && break
    fi
    let n+=200 && pause 0.2
  done
  [ $n -gt 0 ] && msg @. "  waited ${n}ms for ${dev} link"

  rmdir ${ifrc_Lfp}/$dev.lbto 2>/dev/null

  if $phy80211
  then
    grep -qs up /sys/class/net/${dev}/operstate \
    || { msg @. "  ...not associated, deferring"; rc_exit 0; }
  else
    grep -qs 1 /sys/class/net/${dev}/carrier \
    || { msg @. "  ...no cable/link, deferring"; rc_exit 0; }
  fi
}

run_udhcpc() {
  # BusyBox v1.19.3 multi-call binary.
  source /etc/dhcp/udhcpc.conf 2>/dev/null

  # set no-verbose or verbose mode level
  [ -z "$vm" ] && nv='|grep -E "obtained|udhcpc"'
  [ "${vm:2:1}" == "." ] && vb='-v' 
  [ "${vm:1:1}" == "." ] && q=

  # optional exit-no-lease and quit
  nq=

  # request ip-address (given via cmdline)
  rip=${rip:+--request $rip}

  # specific options to request in lieu of defaults
  for t in ${OPT_REQ}; do ropt=$ropt\ -O$t; done
  ropt=${ropt:+-o $ropt}

  # vendor-class-id support (as last line of file or a string)
  vci=$( sed '$!d;s/.*=["]\(.*\)["]/\1/' ${OPT_VCI:-/} 2>/dev/null \
      || echo "$OPT_VCI" )
  vci=${vci:+--vendorclass $vci}
  ropt=${ropt}${vci:+ -O43}

  # specific opt:val pairs to send - must be hex
  for t in ${OPT_SND}; do xopt=$xopt\ -x$t; done

  # request bootfile (via flag-file)
  rbf=${rbf:+-O$rbf}

  # run-script: /usr/share/udhcpc/default.script
  rs='-s/etc/dhcp/udhcpc.script'
  pf='-p/var/run/dhclient.$dev.pid'

  # The run-script handles client states and writes to a leases file.
  # options: vb, log_file, leases_file, resolv_conf
  export udhcpc_Settings="vb=$vb log_file=$ifrc_Log metric=$metric"

  # Client normally continues running in background, and upon obtaining a lease.
  # May be signalled or spawned again depending on events/conditions. Flags are: 
  # iface, verbose, request-ip, exit-no-lease/quit-option, exit-release, retry..
  # For retry, send 4-discovers, paused at 2sec, and repeat after 5sec.
  eval udhcpc -i$dev $vb $rip $nq -R -t4 -T2 -A5 -b $ropt $vci $xopt $rbf $pf $rs $nv

  # spawn a client_wd
  test -x "$CLIENT_WD" \
    && client=udhcpc $CLIENT_WD ${mm:+-v} -i$dev

  #return $?
}

run_dhclient() {
  # Internet Systems Consortium DHCP Client 4.1-ESV-R4
  # Usage: dhclient [-4|-6] [-SNTP1dvrx] [-nw] [-p <port>]
  #                 [-s server-addr]
  #                 [-cf config-file] [-lf lease-file]
  #                 [-pf pid-file] [--no-pid] [-e VAR=val]
  #                 [-sf script-file] [interface]
  #
  # WARNING:
  # some issues not fully vetted...
  # there are many filed bugs and this app contains dead code

  # -cf /etc/dhcp/dhclient.$dev.conf \
  # -pf /var/log/dhclient.$dev.pid \

  dhclient -d -v $dev --no-pid \
   -lf /var/lib/dhcp/dhclient.$dev.leases \
    >/var/log/dhclient.$dev.log 2>&1
  #
  #return $?
}

run_dhcpcd() {
  : dhcpcd is not yet supported
  #
  #return 1 #$?
}

run_dhcp3c() {
  : dhcp3-client is not yet supported
  #
  #return 1 #$?
}

await_timeout_for_dhcp() {
  # wait for ip-address and exit non-zero if timeout...  
  # there will not be any automatic restart nor netlink event
  msg3 "using timeout of $to seconds"
  while [ $to -gt 0 ]
  do
    [ "${vm:0:1}" == "." ] && echo -en .
    pause 1
    let to-=1
    gipa $dev && { to=; break; }
  done
  [ "${vm:0:1}" == "." ] && echo
  if [ -n "$to" ]
  then
    signal_dhcp_client TERM
    msg "  ...no dhcp offer, timeout (error)"
   rc_exit 1
  fi
}

if [ "${methvia/*cfg*/cfg}" != "cfg" ] \
&& [ -n "$pre_cfg_do" ]
then
  msg1 -E "  pre-cfg-do( $pre_cfg_do )"
  make_ "$pre_cfg_do" |tee -a $ifrc_Log & pre_cfg_do=
fi
#
# The interface exists and is ready to be configured.
# And so the specified method and optional parameters will now be applied.
# Note that only the primary ip-address and basic options are handled here.
# Additional configurations may be handled by *-do directives or *.conf's.
#
case ${IFRC_METHOD%% *} in

  dhcp) ## method + optional params
    test -d ${ifrc_Lfp}/$dev.dhcp \
      && { msg1 "  client startup ...already in progress"; rc_exit 0; }

    ifrc_validate_dhcp_method_params

    ## try dhcp renewal first, (re)start client if necessary
    signal_dhcp_client CHECK \
      && make_dhcp_renew_request \
      && rc_exit 0

    check_link
    $conf_resolv -c

    ## allow using a fixed-port-speed-duplex, intended only for wired ports
    if [ ! -d /sys/class/net/$dev/phy80211 ] && [ -n "$mii" ]
    then
      [ -n "$fpsd" ] \
      && $mii -F $fpsd $dev 2>&1 |grep "[vb]a[ls][ue]" 
    fi

    ## maybe add bootfile request option
    [ -n "$rcS_" -a -f /tmp/bootfile_ ] && rbf=bootfile

    mkdir ${ifrc_Lfp}/$dev.dhcp 2>/dev/null \
    && { msg1 "  client ${re}start"; } \
    || { msg1 "  client startup ...already in progress"; rc_exit 0; }
    ## spawn a dhcp client in the background
    # may want to implement a governor to limit futile requests
    # busybox-udhcpc is the most efficient and well maintained
    case ${client:-udhcpc} in
      dhclient)
        run_dhclient &
        ;;
      udhcpc)
        run_udhcpc &
        ;;
      dhcp3c|dhcpc3-client)
        run_dhcp3c &
        ;;
      dhcpcd)
        run_dhcpcd &
        ;;
      *)
        ;;
    esac
    pause 1
    echo -en \\\r 

    rmdir ${ifrc_Lfp}/$dev.dhcp 2>/dev/null
    test -n "$to" && await_timeout_for_dhcp 

    ## restart auto-negotiation after using fixed speed
    # developmental...
    #[ -n "$fpsd" ] && [ -n "$mii" ] && $mii -r $dev >/dev/null
    # well... restoring this has another side-effect...
    # disabled for now, so the fpsd will remain in-effect, if used
    ;;

  static) ## method + optional params
    ifrc_validate_static_method_params
    ## configure interface <ip [+nm] [+gw] [+ns]..>
    #
    if [ -z "$ip" ]
    then
      msg "configuration in-complete, need at least an address: ip=x.x.x.x[/b]"
      ifrc_stop_netlink_daemon
      rc_exit 1
    else
    # ip-addr-modify NIP/NM and BRD
      xip=$( ip addr show dev $dev |sed -n '/inet/{s/.*t \([^ ]*\).*/\1/p;q}' )
      if [ -n "$xip" ]
      then
        fn ip addr add $ip/32 dev $dev
        fn ip addr del $xip dev $dev
      fi
      fn ip addr add $ip${nm:+/$nm} ${bc:+broadcast $bc} dev $dev
      test -n "$xip" \
        && fn ip addr del $ip/32 dev $dev
    fi

    # add default route
    if [ -n "$gw" ]
    then
      # preserve other-default-routes excluding this interface
      odr=$( ip route |sed -n "/via /{/$dev/d;s/^[ \t]*//p}" )

      { read -r ifindex < /sys/class/net/$dev/ifindex; } 2>/dev/null

      # for rt_tables
      if [ -n "$tn" ]
      then
        # determine a weight for the interface
        weight=weight\ ${weight:-${ifindex:-1}}
        nexthop=nexthop
      else
        nexthop=
        odr=
      fi
      default=default

      for ra in $gw
      do
        fn ip route replace $default \
          $nexthop via $ra dev $dev $weight \
            ${odr//default/$nexthop} ;

        # only the first router-addr can be default
        [ -n "$nexthop" ] || default=
      done

      # for rt_tables
      if [ -n "$tn" ]
      then
        # add network and gateway routes to table
        fn ip route add $network/$subnet dev $dev src $ip table $tn
        fn ip route add default via $ra dev $dev table $tn
        # rewrite policy rules in the lookup table
        while ip rule del not table $tn 2>/dev/null; do :;done
        fn ip rule add from ${ip}/32 lookup $tn  ### outgoing ##
        fn ip rule add to ${ip}/32 lookup $tn  ### incoming ##
      fi
      fn ip route flush cache
    fi

    # update w/validated nameserver
    $conf_resolv -a $dev nameserver $ns
    ;;

  loopback) ## method + optional params
    ifrc_validate_loopback_method_params
    # operstate can be down or unknown(up)
    # using a default address if none specified
    # an 'ip link set up' may auto-config the default
    fn ip addr add ${ip:=127.0.0.1/8} dev $dev 2>/dev/null
    ;;

  manual) ## method ...no params
    ifrc_validate_manual_method_params
    # do nothing, configuration is to be handled manually
    ;;

  *) ## error
    x=${IFRC_METHOD%% *}
    msg "  ...unhandled, configuration method: ${x/=*/=} (error)"
    msg "  methods:  manual, loopback, static, dhcp"
    msg "  more info, try:  ifrc -h"
    rc_exit 1
    ;;
esac
#
# Only can get to this point if we successfully (re-)configured the interface.
# If using dhcp, then must employ a timeout, to be certain.
#
if [ "${methvia/*cfg*/cfg}" != "cfg" ] \
&& [ -n "$post_cfg_do" ]
then
  msg1 -E "  post-cfg-do( $post_cfg_do )"
  make_ "$post_cfg_do" |tee -a $ifrc_Log & post_cfg_do=
fi
rc_exit 0
