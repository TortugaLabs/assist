#!/bin/sh
ver=0.3dev
##
## ASSIST (<VER>)
## ==============
## _Arch System Software Installation Scripting Tool_
##
## _ASSIST_ is a script utility used for new Arch Linux installs.
##
## It aims to be a very simple installation script that essentially
## follows what the install instructions say without trying to be too
## smart about it.
##
## It also is meant to be easy to deploy/inject into installations and
## aims to be extensible enough that additional features can be added
## and the installation be mostly automated.
##
## _ASSIST_ does not try to handle all possible installation cases nor
## tries to implement all the features available in the old AIF
## scripts.
##
## Using ASSIST
## ============
##
## If used without arguments, _ASSIST_ will attempt to perform an
## archlinux install.
##
######################################################################
#
# This is the main setup function.  The bulk of the work happens
# here.
#
# Except for the first two function calls, all the functions in
# `assist_setup` can be overriden.
#
assist_setup() {
    exec </dev/tty >/dev/tty 2>&1
    # - preparation (i.e. no network required)
    assist_preconfig "$@"
    assist_preinput
    # - configuration either from network or from user input
    assist_setup_config "$@"
    assist_setup_input
    # - point of no return
    assist_ready_to_commit
    # - bulk of the work
    assist_install
    # - final tweaks
    assist_post_input
    # - final clean-up
    assist_finalize
    echo ''
    echo "DONE"
    # Make sure we exit otherwise it hangs (tries to read for stdin)
    exit
}
## It will do so in the following stages:
##
## - `pre-config` : Usually configuration through command line paramenters
##   entered as boot command options, arguments to _ASSIST_ or environment
##   variables.
## - `pre-input` : Some basic configuration that might need to happen *before*
##   we have an available network
## - `setup config` : Perform any (network based) configuration activities.
## - `setup input` : Collect additional input on how the installation needs
##   to be performed.
## - `installation` : Performs the bulk of the install task.
## - `Post input` : Perform some post installation activities
##
## Invoking _ASSIST_
## ---------------
##
## _ASSIST_ can be invoked to install Arch Linux in a number of ways
##
##
## ### From the net
## 
## You need to make sure that you have a working internet connection.
## Enter the following:
##
##        wget -O- https://raw.github.com/alejandroliu/assist/master/assist.sh | sh
##
##
## ### Injecting into INITRAMFS boot
##
##        assist.sh inject _orig.img_ _new.img_
##
## It will edit an initrd cpio image and will create a hook that will
## arrange for _ASSIST_ to run automatically.
##
## This is particularly useful for automated installation using a PXE
## environment.
##
######################################################################
##
## Running the installation
## ------------------------
##
## ### Pre-configuration
##
## Initially _ASSIST_ will ask the user for some pre-configuration information
##
## - Keyboard layout
## - Network Setup
assist_preinput() {
    assist_kbdlayout
    assist_netsetup
}
##
## #### Keyboard Layout
##
assist_kbdlayout() {
  if [ -n "$kbd" ] ; then
    echo "Loading default keyboard: $kbd"
    loadkeys $kbd && return
  fi
  # Create a list of available keymaps...
  local i ks=($dftkbd '')
  for i in $(cd /usr/share/kbd/keymaps/$kbd_platform && echo */*)
  do
    i=$(basename $i .gz | sed 's/\.map$//')
    [ $i = $dftkbd ] && continue
    ks+=($i '')
  done
  kbd=$(dlg --menu "Select your keyboard layout" 0 0 0 "${ks[@]}") \
      || kbd="$dftkbd"
  loadkeys $kbd || pause
}
## For many countries and keyboard types appropriate keymaps are available 
## already, and a command like `loadkeys uk` might do what you want. More 
## available keymap files can be found in `/usr/share/kbd/keymaps/` 
## (you can omit the keymap path and file extension when using `loadkeys`). 
##
## _ASSIST_ will look in `/usr/share/kbd/keymaps/` and let you select a
## Keymap from there.
##
## #### Networking
##
## Usually a DHCP service is already enabled for all available devices.  
## Somtimes this may fail, or you need to configure either _wireless_
## or _static IP_.
##
assist_netsetup() {
  # Configured through PXE...
  [ -n "$cf_ip" -a -n "$cf_BOOTIF" ] && return

  if ! no_dft_gw ; then
    [ -n "$auto_continue" ] && return
    dlg --yesno "You already have a running network.

Do you want to keep your current network settings?

YES - will continue installation
NO  - will let you configure network settings" 0 0 && return
  fi

  # Wireless
  local wifi=$(
      [ -f /proc/net/wireless ] || exit
      exec < /proc/net/wireless
      read x ; read x
      cut -d: -f1
  )
  local netdevs=$(
      [ -f /proc/net/dev ] || exit
      exec </proc/net/dev
      read x
      read y
      grep -v '^ *lo:' | cut -d: -f1
  )
  [ $(wc -w <<<"$netdevs") -eq 0 ] \
      && fatal "No available network interfaces found"

  local opts=(
      "dhcp" "Configure DHCP"
      "static" "Configure static networking"
  )
  [ $(wc -w <<<"$wifi") -gt 0 ] && opts+=( "wifi" "Configure wireless" )

  while :
  do
    local op=$(dlg \
	--menu "Network Configuration Options" 0 0 0 \
	$(no_dft_gw || echo 'ready' 'done') \
	"${opts[@]}")
    [ -z "$op" ] && aborted
    case "$op" in
      dhcp)
	assist_net_dhcp $netdevs
	;;
      static)
	assist_net_static $netdevs
	;;
      wifi)
	assist_net_wifi $wifi
	;;
      ready)
	return
	;;
    esac
  done
}
##
## There are three (3) options for network configuration:
##
## 1. `dhcp` : for the case that `dhcpcd` failed to start.
## 2. `static` : To enter static IP addresses.
## 3. `wifi` : for configuring Wireless networks
##
assist_net_dhcp() {
  local cif=$(pick_netif $*)
  dhcpcd $cif
  pause
}
assist_net_static() {
  local cif=$(pick_netif $*)
  local opts=$(dlg --form "Enter network settings for $cif" 0 0 0 \
      "IP address" 1 0 "0.0.0.0" 1 12 16 16\
      "Netmask"	   3 0 "255.255.255.0" 3 12 16 16 \
      "Gateway"	   5 0 "0.0.0.0" 5 12 16 16 \
      "DNS"	   7 0 	"0.0.0.0" 7 12 16 16)
  [ -z "$opts" ] && aborted

  eval "$(echo "$opts" | (
      read ip ; read netmask ; read gw ; read dns
      declare -p ip netmask gw dns | sed 's/declare --/local /'
  ))"
  if ! ifconfig $cif "$ip" netmask "$netmask" ; then
    pause
    return
  fi
  if ! route add default gw "$gw" $cif ; then
    pause
    return
  fi
  cat > /etc/resolv.conf <<-EOF
	nameserver $dns
	EOF
}
assist_net_wifi() {
  local cif=$(pick_netif $*)
  wifi-menu || pause
}
##
######################################################################
##
## ### Set-up customization
##
## Once we have a proper keyboard layout and a working network,
## _ASSIST_ will attempt to customise your installation.
##
## - hostname
## - partitioning schema
## - bootloader
## - pacman mirrors
## - software groups
## - locale and timezone
##
assist_setup_input() {
  # Prompt the user for configuration parameters...
  assist_input_hostname
  assist_input_partition
  assist_input_bootloader
  assist_input_mirrors
  assist_input_software
  assist_input_tz
  assist_input_locale
}
#
assist_input_hostname() {
  [ -n "$sysname" ] && return
  sysname=$(dlg --inputbox "enter hostname for this system" 0 0 "")
  [ -z "$sysname" ] && aborted
}

##
## #### Partitioning
##
assist_input_partition() {
  [ -n "$target" -a -n "$autopart" ] && return

  partmode=$(dlg \
      --menu "Partitioning mode" 0 0 0 \
      "autopart" "Automatically partition a single drive" \
      "none" "Uses the current partitioning scheme"
  )
  [ -z "$partmode" ] && aborted

  assist_inputpart_$partmode
}
## _ASSIST_ has two (2) different partitioning modes:
##
## 1. `autopart` - mostly automated partitioning for a single drive
##     configuration
## 2. `none` - assumes that the user created and mounted partitions already
##
## ##### autopart
##
## Autopartitioning will let you select one drive (if there are more than
## one).
pick_disc() {
  [ $# -eq 0 ] && return
  if [ $# -eq 1 ] ; then
    echo $1
    return
  fi
  local i opts=()
  for i in $*
  do
    opts+=( $i "$(cat /sys/block/$i/device/model)" )
  done
  dlg --menu "Select disc to install to" 0 0 0 \
      "${opts[@]}"
}
##
## _ASSIST_ will apply a basic partitioning schema on the selected disc:
##
## - `/` : root partition (ext4, 15G)
## - `/boot` : boot partition (ext2, 128M)
## - `swap` : swap partition (2G)
## - `/home` : will use the rest of the disc
##
## While the mountpoints and filesystem types are fixed, _ASSIST_ will give
## you an opportunity to change the sizes and/or remove partitions.
##
## When changing partition sizes, entering a value of "`0`" wil cause
## that partition to *not* be created.  While entering an _empty_ or
## _blank_ size, will make that partition as large as possible.
##

assist_inputpart_autopart() {
  if [ -z "$target" ] ; then
    while :
    do
      target=$(pick_disc $(find_discs))
      [ -z "$target" ]  && fatal "No installable discs selected or found"
      dlg --defaultno --yesno "THIS WILL CLEAR ALL DATA IN $target $(cat /sys/block/$target/device/model)

Are you sure you want to continue?" 0 0 && break
    done
  fi

  [ -n "$autopart" ] && return
  while :
  do
    local fsizes=$(dlg --form "Partition profile

Enter the sizes of the different Linux partitions to use.
Leaving a field blank \"\" will make that partition as large as possible.
Set to \"0\" (zero) if you do not want to create that partition.

WARNING: This will ALWAYS create a GPT Partition
" 0 0 0 \
    "/"	1 0 "15G" 1 12 8 0 \
    "/boot"	2 0 "128M" 2 12 8 0 \
    "swap"	3 0 "2G"  3 12 8 0 \
    "/home" 4 0 "" 4 12 8 0)
    [ -z "$fsizes" ] && aborted
    eval $(echo "$fsizes" | (
	    read root ; read boot ; read swap ; read home
	    declare -p root boot swap home | sed 's/declare --/local /'
	    ))

    local x q=""
    local postpart=""
    autopart=""
    for x in "/boot:$boot" "/:$root" "swap:$swap" "/home:$home"
    do
      IFS=":" ; set - $x ; IFS="$oIFS"
      if [ "$2" = "0" ] ; then
	if [ "$1" = "/" ] ; then
	   pause "You must have a root (/) partition"
	   continue 2
	fi
	continue
      fi
      local sz="$2"
      if [ -z $sz ] ; then
	if [ -n "$postpart" ] ; then
	  pause "You can only have one autosize partition ($1 $postpart)"
	  continue 2
	fi
	postpart="$1 _"
      else
	autopart="$autopart$q$1 $sz"
      fi
      q=" "
    done
    [ -n "$postpart" ] && autopart="$autopart $postpart"
    break
  done
}
##
## ##### none
##
## This option assumes that the user already has prepared the installation
## target and that it is mounted under `/mnt`.
##

assist_inputpart_none() {
  if dlg --yesno "Have you already prepared your install media and mounted it under /mnt?" 0 0 ; then
    nparts /mnt || fatal "No partitions found under /mnt"
  else
    echo ''
    echo 'You must first partition your installation media and mount it'
    echo 'under /mnt.  After that is done you can re-run setup'
    echo ''
    exit
  fi
  target=""
  autopart=""
}

##
## #### Bootloader
##
## In the spirit of keeping things simple, _ASSIST_ defaults to *SYSLINUX*`
## for the bootloader.  
##

assist_input_syslinux() {
  # Input bootloader options
  add_sw_dep syslinux
}

assist_input_bootloader() {
  #if [ -z "$bootloader" ] ; then
  #  bootloader=$(dlg --menu "Select bootloader to use" 0 0 0 syslinux "" grub "")
  #  [ -z $bootloader ] && aborted
  #fi
  bootloader="syslinux"
  assist_input_$bootloader
}

##
## #### Mirror lists
##
## This lets you customize the pacman mirror list.
##
## This copy of the mirrorlist will be installed on your new system by 
## pacstrap as well, so it's worth getting it right.
##
## The following options are available:
##
## - `edit`  
##   Simply edit the mirrorlist using a text editor
## - `country`  
##   Will generate a mirror list based on your country.
## - `none`  
##   Simply use the existing mirrorlist.
##
assist_input_mirrors() {
  local lst=/etc/pacman.d/mirrorlist
  if [ -n "$mirrorlist" ] ; then
    if [ -f "$mirrorlist" ] ; then
      cat "$mirrorlist" > $lst
      return
    else
      newlst=$(mktemp)
      if wget -O- "$mirrorlist" > $newlst ; then
	if [ $(wc -l < $newlst) -gt 0 ] ; then
	  cat $newlst > $lst
	  rm -f $newlst
	  return
	fi
      fi
      rm -f $newlst
    fi
  fi

  if [ -n "$country" ] ; then
    # Customised base on country
    assist_mirror_by_country $lst "$country"
    return
  fi

  local op=$(dlg --menu "Do you want to customise your preferred mirrors?

This copy of the mirrorlist will be installed on your new system by pacstrap as well, so it's worth getting it right." 0 0 0 \
    "edit" "Use an editor on the mirrorlist" \
    "country" "Generate a mirror list based on your country" \
    "none" "Use the mirror list as-is")
  [ -z "$op" ] && aborted

  case "$op" in
    edit)
      edit $lst
      ;;
    country)
      # Select country
      local countries=(
	  "AU" "Australia" 
	  "BY" "Belarus"
	  "BE" "Belgium" 
	  "BR" "Brazil" 
	  "BG" "Bulgaria" 
	  "CA" "Canada" 
	  "CL" "Chile" 
	  "CN" "China" 
	  "CO" "Colombia" 
	  "CZ" "Czech Republic" 
	  "DE" "Denmark" 
	  "EE" "Estonia" 
	  "FI" "Finland"
	  "FR" "France" 
	  "DE" "Germany" 
	  "GR" "Greece" 
	  "HU" "Hungary" 
	  "IN" "India" 
	  "IE" "Ireland" 
	  "IL" "Israel" 
	  "IT" "Italy" 
	  "JP" "Japan" 
	  "KZ" "Kazakhstan" 
	  "KR" "Korea" 
	  "LV" "Latvia" 
	  "LU" "Luxembourg" 
	  "MK" "Macedonia" 
	  "NL" "Netherlands" 
	  "NC" "New Caledonia"
	  "NZ" "New Zealand" 
	  "NO" "Norway" 
	  "PL" "Poland" 
	  "PT" "Portugal" 
	  "RO" "Romania" 
	  "RU" "Russian" 
	  "RS" "Serbia" 
	  "SG" "Singapore" 
	  "SK" "Slovakia" 
	  "ZA" "South Africa"
	  "ES" "Spain" 
	  "LK" "Sri Lanka" 
	  "SE" "Sweden" 
	  "CH" "Switzerland" 
	  "TW" "Taiwan" 
	  "TR" "Turkey" 
	  "UA" "Ukraine" 
	  "GB" "United Kingdom" 
	  "US" "United States" 
	  "UZ" "Uzbekistan" 
	  "VN" "Viet Nam"
      )
      country=$(dlg --menu "Select your country" 0 0 0 "${countries[@]}")
      [ -z $country ] && aborted
      assist_mirror_by_country $lst "$country"
      dlg --yesno "Do you want to edit/review the mirror list?" 0 0 \
	  && edit $lst
      ;;
  esac
}
##
## When configuring by country, you will select a country and this will
## in turn use the URL:  
##
## <https://www.archlinux.org/mirrorlist/?country=$country&protocol=ftp&protocol=http&ip_version=4&use_mirror_status=on>
##
## To create an initial mirrorlist.  Then you may review and modify it.
##
assist_mirror_by_country() {
  local lst="$1" country="$2"

  local url="https://www.archlinux.org/mirrorlist/?country=$country&protocol=ftp&protocol=http&ip_version=4&use_mirror_status=on"
  local tmpfile=$(mktemp --suffix=-mirrorlist)
  wget -qO- "$url" | sed 's/^#Server/Server/g' > "$tmpfile"
  [ ! -f $lst.bak ] && cp $lst $lst.bak
  cat $tmpfile >$lst.bak
}
##
## ### Software Selection
##
## This will let you customise the initial software selection.  Note that
## this is just a subset of all the software available in ArchLinux.
## The idea is that this is enough software to bootstrap your system.
## You can then later use `pacman` to add any additional software.
##
assist_input_software() {
  [ -n "$sw_list" ] && return
  # Select the software to use...
  local opts i j k
  for j in mandatory:on recommended:on suggested:off optional:off
  do
    IFS=":" ; set - $j ; IFS="$oIFS"
    for i in $(eval echo \$sw_$1)
    do
      opts+=( $i "$1"  "$2" )
    done
  done
  sw_list=$(dlg --checklist "Select software to install" 0 0 0 "${opts[@]}" | tr -d '"' )
  [ -z "$sw_list" ] && aborted
}

##
## ### Locale and timezone
##
## This lets you specify the locale you want to use and the timezone
## you are located in.
##

assist_input_tz() {
  [ -n "$tz" ] && return
  
  local zone subzone zlst szlst i zdir=/usr/share/zoneinfo back="<back>"
  zlst=()
  for i in $(ls -1 $zdir)
  do
    if [ -f $zdir/$i ] ; then
      (file $zdir/$i | grep -q 'timezone data') || continue
    fi
    zlst+=( $i "" )
  done
  while :
  do
    zone=$(dlg --menu "Configure Time zone

Select Region" 0 0 0 "${zlst[@]}")
    [ -z "$zone" ] && aborted
    if [ -d $zdir/$zone ] ; then
      szlst=("$back" "")
      for i in $(ls -1 $zdir/$zone)
      do
	szlst+=( $i "")
      done
      subzone=$(dlg --menu "Configure Time Zone

Select City" 0 0 0 "${szlst[@]}")
      [ -z "$subzone" ] && aborted
      [ "$subzone" = "$back" ] && continue
      tz="$zone/$subzone"
      return
    fi
    tz="$zone"
    return
  done
}

assist_input_locale() {
  [ -n "$locale" ] && return
  locale=$(dlg --default-item 'en_US.UTF-8' --menu "Enter locale" 0 0 0 \
      $(grep '^#*[a-z][a-z].*[ 	].*$' /etc/locale.gen | sed -e 's/#//' ))
  [ -z "$locale" ] && aborted
}
######################################################################
##
## ### Installation
##
## After entering all the setup customisations, _ASSIST_ will perform the
## installation.
##
## Normally this would include:
##
## - paritioning the target disc
## - installing selected software
## - creating the `fstab` file
## - installing a bootloader
## - configuring the system:
##   - hostname
##   - timezone
##   - locale
## - set-up a basic `dhcp` based `netcfg` profile 
## - create a initramfs file
##
## This is a good time to take a coffee break.
##
assist_install() {
  assist_inst_partition
  nparts /mnt || fatal "No partitions found under /mnt"
  assist_inst_pre
  assist_inst_sw
  assist_inst_fstab
  assist_inst_$bootloader
  assist_inst_hostname
  assist_inst_tz
  assist_inst_locale
  assist_inst_netcfg
  assist_inst_mkinitcpio
  assist_inst_post
}
######################################################################
##
## ### Post Install tasks
##
assist_post_input() {
    assist_root_pwd
    assist_new_user
}
##
## Once installation is completed you _ASSIST_ will run through final
## customisation activities:
##
## - change root password
## - create users
##
assist_root_pwd() {
  echo "Setting root password"
  arch-chroot /mnt sh -c 'while ! passwd ; do : ; done'
}
##
## #### Changing the root password
##
## It is very important to secure your system with a strong password.
## By default _ASSIST_ will prompt you to enter a new root password
## when the installation finishes.
##
assist_new_user() {
  [ -n "$auto_continue" ] && return
  local uid_min=$(grep '^UID_MIN' /mnt/etc/login.defs|awk '{print $2}')
  while dlg --yesno "Do you want to create a new user?

The following users are currently defined in the system:

$(awk -F: '$3 >= '$uid_min' { print $1}' /mnt/etc/passwd | tr '\n' ' ')" 0 0 
  do
    echo ''
    echo -n "Enter username: "
    read new_user
    [ -z "$new_user" ] && continue
    arch-chroot /mnt sh -c "( useradd -m -g users -s /bin/bash $new_user && chfn $new_user && passwd $new_user ) || read -p 'Press Enter: ' none"
  done
}
##
## #### Creating users
##
## It is important that you do not run your system as a root (adminstrative)
## user.  So it is highly recommended to always create user accounts for
## normal system usage.
##
## At the end of the installation _ASSIST_ will let you create new users.
##
######################################################################
##
## Automating _ASSIST_ installations
## ===============================
##
## _ASSIST_ is designed to allow automated installs.  Most of the input
## prompts in the installations can be given suitable defaults so that
## they do not need to be entered by the user.
##
## Configurable variables
## ----------------------
##
## The following configuration variables are recognised:
##
assist_cfg_defaults() {
  ## - `kbd` : Keyboard layout to use
  kbd=""
  ## - `sysname` : System host name
  sysname=""
  ## - `autopart` : Automatic partition configuration
  autopart=""
  ## - `target` : Target disc to install to
  target=""
  ## - `mirrorlist` : file or url to use for initialising the pacman mirrorlist
  mirrorlist=""
  ## - `sw_list` : list of software to install
  sw_list=""
  ## - `bootloader` : Boot loader configuration
  bootloader=""
  ## - `tz` : Time zone
  tz=""
  ## - `locale` : System localisation
  locale=""
  ##
  ## In addition, the following boolean variables control user interaction
  ## 
  ## - `auto_continue` : will skip some of the prompts
  auto_continue=""
  ## - `no_pause : will skip all `pause` prompts.
  no_pause=""
  ##
  ## Finally, these additional variables configure certain aspects
  ## of the installation:
  ##
  ## - `kbd_platform` (`i386`): Used to determine the keymaps to show
  kbd_platform=i386
  ## - `dftkbd` (`us`): The default keyboard to offer the user
  dftkbd=us
  ## - `sw_mandatory` : The list of mandatory software packages to be shown
  ##    during software selection.
  sw_mandatory="base"
  ## - `sw_recommended` : The list of recommended packages
  sw_recommended="gptfdisk"
  ## - `sw_suggested` : The list of suggested packages
  sw_suggested="wget php dialog ed pm-utils mkinitcpio-nfs-utils nfs-utils ethtool net-tools ifplugd openssh autofs ntp"
  ## - `sw_optional` : List of optional packages.
  sw_optional="base-devel"
  ## - `sw_deps` : Contains the list of software added by _ASSIST_ dependancies.
  sw_deps=""
}
##
## Defining configuration defaults
## -------------------------------
##
## Configuration defaults can be achieved through boot parameters,
## command line argumets, environment variables or configuration
## scripts.
##
## ### Kernel boot command line
##
## _ASSIST_ will examine the kernel boot command line and look for
## configuration parameters begining with `assist_`.  So if you want
## to configure the `kbd` variable to `us` in the boot command line you
## would enter:
##
##     assist_kbd=us
##
## Boolean variables can be specified as this:
##
##     assist\_auto\_continue
##
assist_kcmdline_cfg() {
  [ ! -f /proc/cmdline ] && return
  for setting in $(cat /proc/cmdline)
  do
    IFS="=" ; set - $setting ; IFS="$oIFS"

    local vname="$1"
    if grep -q '^assist_' <<<"$vname" ; then
      vname=$(sed 's/^assist_//' <<<"$vname")
    else
      vname="cf_$vname"
    fi
    if [ $# -eq 1 ] ; then
      eval $vname="$1"
    else
      shift
      eval $vname=\"\$\*\"
    fi
  done
  [ -n "$cf_src" ] && src="$cf_src"
}
##
## ### command line
##
## _ASSIST_ can be invoked with command line parameters:
##
##        assist setup [opts ...]
##
## Because _ASSIST_ accepts multiple sub-commands, you must specify the
## `setup` option (which is the default if no arguments are used).
##
## The arguments after that are either boolean or key-value pairs specifying
## the default options.  For example:
##
##        assist setup kbd=us auto_continue
##
assist_parse_args() {
  local setting
  for setting in "$@"
  do
    IFS="=" ; set - $setting ; IFS="$oIFS"

    if [ $# -eq 1 ] ; then
      eval $1="$1"
    else
      local v="$1" ; shift
      eval $v=\"\$\*\"
    fi
  done
}
##
## ### Environment variable
##
## _ASSIST_ will exammine the `ASSIST_ARGS` environment variable.  if
## found, its contents would be interpreted in the same way as the
## command line arguments
##
assist_preconfig() {
    assist_cfg_defaults
    assist_kcmdline_cfg
    assist_parse_args "$@"
    [ -n "$ASSIST_ARGS" ] && assist_parse_args $ASSIST_ARGS
}
##
## ### Configuration files
##
## You can also load defaults from configuration files. These are
## specified from the boot prompt or the command line with:
##
##        src=_path or url to config file_
##
## (Note that unlike boot variables that need the `assist_` prefix, 
## configuration scripts only need `src` to be specified.)
##
assist_autocfg() {
  # 1. check if we need to retrieve settings
  [ -z "$src" ] && return
  local url
  for url in $([ -f /proc/cmdline ] && cat /proc/cmdline) "$@"
  do
    IFS="=" ; set - $url ; IFS="$oIFS"
    [ "$1" != "src" ] && continue
    [ $# -eq 1 ] && continue
    url=$(cut -d= -f2- <<<"$url")
    assist_src $url
  done
}
##
## The `src` entry may point to either a file or an URL.  The contents
## of the `src` files are standard `bash` scripts that are sourced
## by _ASSIST_.  This means that you not only can use it define defaults,
## but can be used to define new additional functionality for _ASSIST_.
##
assist_src() {
  local url="$1"
  if [ -f  $url ] ; then
    . $url
  else
    local x=$(mktemp)
    if wget -O- $url > $x ; then
      . $x
      rm -f $x
    else
      [ -n "$auto_continue" ] && return
      dlg --yesno "Unable to retrieve autoconfig script: 

$url.

Do you want to continue?
(Selecting NO will stop this script" 0 0 || aborted
    fi
  fi
}
##
## Keep in mind that even though you can use `src` to define defaults,
## the command line settings and environment variables will always
## take precendence over `src` settings or kernel boot parameters.
##
assist_setup_config() {
    assist_autocfg "$@"
    assist_parse_args "$@"	# Let cmd line override autocfg!
    [ -n "$ASSIST_ARGS" ] && assist_parse_args $ASSIST_ARGS
}
##
## As mentioned earlier, `src` files are standard bash scripts.  You
## can use it to add additional functionality to _ASSIST_.  Essentially
## all of _ASSIST_ is modular and can be overriden by a `src` script
## by simply defining a new function.
##
## For convenience the following functions are defined:
##
## - `assist_inst_pre`  
##    By default it is empty, but is executed right at the beginning
##    of the installation.
## - `assist_inst_post`  
##    Similarly, empty by default, but gets executed towards the
##    end of the install.
##
## You are encouraged to peek in the _ASSIST_ script to find out what
## functions are defined so you can override them.
##
######################################################################
#
assist_inst_pre() {
    :
}
assist_inst_post() {
    :
}
######################################################################
##
## ### Using configuration defaults
##
## Configuration defaults can be entered interactively but normally it
## is expected to be entered into the installation media or through
## the DHCP server that drives a PXE boot install.
##
##
## _ASSIST_ Installation Details
## ===========================
##
## This section describes what _ASSIST_ does when performan an install.
##
## Partitioning
## ------------
##
## This is configured by `target` and `autopart` variables.
## The function to override is `assist_inst_partition`.  Because
## the bootloader is tightly integrated with the partitioning,
## there are two additional override functions: 
##
## - `assist_inst_part1_$bootloader`
## - `assist_inst_part2_$bootloader`
##
## The default paritioning will create a GPT partioning table.
## After that partitions will be formated (`mkswap` or `mkfs`) and
## mounted automatically under `/mnt`.
## 
assist_inst_part1_syslinux() {
  # Make sure that we have a valid boot record
  dd bs=440 conv=notrunc count=1 if=/usr/lib/syslinux/gptmbr.bin of=$disc \
       || exit 1
}
assist_inst_part2_syslinux() {
  sgdisk --attributes=$boot_part:set:2 || exit 1
}

assist_inst_partition() {
  [ -z "$target" -o -z "$autopart" ] && return
  
  # Clear partition data
  local disc=/dev/$target
  sgdisk --zap-all $disc || exit 1
  sgdisk --clear $disc || exit 1

  # Create partitions
  set - $autopart
  local boot_fs="/" pn=0

  local devs=""
  assist_inst_part1_$bootloader

  while [ $# -gt 0 ]
  do
    local fs=$1 sz=$2 ; shift 2
    [ $fs = "/boot" ] && boot_fs=$fs
    pn=$(expr $pn + 1)
    if [ $sz = "_" ] ; then
      sgdisk --largest-new=$pn $disc || exit 1
    else
      sgdisk --new=$pn:0:+$sz $disc || exit 1
    fi
    if [ $fs = "swap" ] ; then
      sgdisk --type=$pn:8200 $disc || exit 1
    else
      sgdisk --type=$pn:8300 $disc || exit 1
    fi
    if [ -z "$devs" ] ; then
      devs="$fs $pn"
    else
      devs="$devs
$fs $pn"
    fi
    [ $fs = $boot_fs ] && boot_part=$pn
  done

  assist_inst_part2_$bootloader

  set - $(sort <<<"$devs")
  while [ $# -gt 0 ]
  do
    local fs=$1 pn=$2 ; shift 2
    if [ $fs = "swap" ] ; then
      mkswap -L swap$pn $disc$pn || exit 1
      swapon $disc$pn || exit 1
    else
      fstype=ext4
      [ $fs = "/boot" ] && fstype=ext2
      mkfs -t $fstype -L $fs $disc$pn || exit 1
      tune2fs -i0 -c0 $disc$pn || exit 1
      mkdir -p /mnt$fs || exit 1
      mount -t $fstype $disc$pn /mnt$fs
    fi
  done
}

##
## Software installation
## ---------------------
## 
## This is configured by `sw_list` and `sw_deps` variables.
## The function to override is `assist_inst_sw`.
##
## Will run `pacstrap` to install the selected software.
##
assist_inst_sw() {
  pacstrap /mnt $(echo $sw_list $sw_deps | tr ' ' '\n' | sort -u)
}
##
## System configuration
## --------------------
##
## The following configuration tasks happen after software install:
##
## ### fstab
##
## Function to override `assist_inst_fstab`.
##
## Create a new `fstab` file using `genfstab`
##
assist_inst_fstab() {
  genfstab -p -U /mnt >> /mnt/etc/fstab
}
## ### bootloader
##
## Function to override: `assist_inst_$bootloader`
##
## #### syslinux
##
## Will modify the `syslinux.cfg` file to point to the right `root`
## device and also will add the `nomodeset` parameter if it was
## specified when booting the installation media.
##
assist_inst_syslinux() {
  local rootdev=$(awk '$2 == "/mnt" { print $1 }' < /proc/mounts)

  local sed_opts=(
      -e 's!root=[^ 	]*!root='"$rootdev"'!'
  )
  # OK, do we need to add modeset to the APPEND lines...
  grep -q nomodeset /proc/cmdline && sed_opts+=(
      -e 's/APPEND[ 	][ 	]*root=/APPEND nomodeset root=/'
  )
  sed -i~ \
       "${sed_opts[@]}" \
      /mnt/boot/syslinux/syslinux.cfg
  arch-chroot /mnt /usr/sbin/syslinux-install_update -iam
}
##
## ### hostname
##
## Configured with `sysname` variable.
## Function to override: `assist_inst_hostname`.
##
## Will set the `hostname` for the newly installed system.
##
assist_inst_hostname() {
  [ -n "$sysname" ] && echo $sysname > /mnt/etc/hostname
}
## ### Timezone
##
## Configured with `tz` variable.
## Function to override: `assist_inst_tz`.
##
## Configure the local timezone for the system.
##
assist_inst_tz() {
  rm -f /mnt/etc/localtime
  if [ -n "$tz" ] ; then
    ln -s /usr/share/zoneinfo/$tz /mnt/etc/localtime
  else
    ln -s /usr/share/zoneinfo/UTC /mnt/etc/localtime
  fi
}

## #### Locale
##
## Configured with `kbd`, `locale` variables.
## Function to override: `assist_inst_locale`.
##
## Configures the keyboard layout in `/etc/vconsole.conf` and
## the system locale in `/etc/locale.conf` and `/etc/locale.gen`.
##
assist_inst_locale() {
  cat >/mnt/etc/vconsole.conf <<-EOF
	KEYMAP=$kbd
	FONT=
	FONT_MAP=
	EOF
  cat >/mnt/etc/locale.conf <<-EOF
	LANG=$locale
	EOF

  sed -i~ \
      -e "s/^#*$locale/$locale/" \
      /mnt/etc/locale.gen
  arch-chroot /mnt locale-gen
}
## #### Network
##
## Function to override: `assist_inst_netcfg`.
##
## Creates a basic `netcfg` profile for all the wired interfaces
## found in the system.
##
assist_inst_netcfg() {
  local net_profiles="" dev wdev np oldnames=n

  # Basic netcfg install
  for dev in $(grep '^ *[a-z0-9]*:' /proc/net/dev | cut -d: -f1 | grep -v lo )
  do
    local wifi=no
    for wdev in $(grep '^ *[a-z0-9]*:' /proc/net/wireless | cut -d: -f1 )
    do
      [ "$wdev" != "$dev" ] && continue
      wifi=yes
      break
    done
    [ $wifi = yes ] && continue
    # Determine if we are using oldstyle/newstyle names
    grep -q '^eth' <<<"$dev" && oldnames=y

    net_profiles="$net_profiles net-$dev"
    cat >/mnt/etc/network.d/net-$dev <<-EOF
	CONNECTION='ethernet'
	DESCRIPTION='Basic dhcp config for $dev'
	INTERFACE='$dev'
	IP='dhcp'
	# # For DHCPv6
	#IP6='dhcp'
	# # for IPv6 autoconf
	#IP6='stateless'
	EOF
  done

  for np in $net_profiles
  do
      arch-chroot /mnt systemctl enable netcfg@$np.service
  done
  if [ $oldnames = y ] ; then
    echo "Disabling predictable Network Interface names..."
    ln -s /dev/null /mnt/etc/udev/rules.d/80-net-name-slot.rules
  fi
}

##
## ### initramfs
##
## Function to override: `assist_inst_mkinitcpio`.
##
## Configures the initramfs contents.
##
assist_inst_mkinitcpio() {
    arch-chroot /mnt mkinitcpio -p linux "$@"
}
#
######################################################################
##
## Command-line
## ============
##
##     assist {sub_cmd} [args]
##
## Available sub commands:
##
assist_main() {
  local op="$1" ; shift
  case "$op" in
    inject)
      ## - `inject` - Injects _ASSIST_ into a `initrd` image.
      assist_inject "$@"
      ;;
    doc)
      ## - `doc` - display documentation
      assist_doc "$@"
      ;;
    setup)
      ## - `setup` - Performs an ArchLinux install
      assist_setup "$@"
      ;;
    *)
      fatal "ASSIST Unknown sub-command: $op"
      ;;
  esac
}
##
## The default sub-command if none is specified is `setup`.
##
[ $# -eq 0 ] && set - setup

######################################################################
##
## Utility Sub Commands
## ====================
##
## doc
## ---
##
## Displays the on-line documentation for _ASSIST_
##
## Usage:
##
##        assist doc [options]
##
## Options:
##
assist_doc() {
  if [ $# -eq 0 ] ; then
    if [ -n "$DISPLAY" ] ; then
      set - viewhtml
    else
      set - text
    fi
  fi

  grep '^[ 	]*## *' < "$0" | grep -v '^[ 	]*###' | sed \
      -e "s/<VER>/$ver/" \
      -e 's/^[ 	]*##[ 	]*$//' \
      -e 's/^[ 	]*## //' \
      -e 's/^[ 	]*##	/	/' | (
      case "$1" in
	text)
	  ## - `text` : plain text output
	  cat
	  ;;
	html)
	  ## - `html` : HTML document
	  markdown
	  ;;
	viewhtml)
	  ## - `viewhtml` : Will show manual on a browser window.
	  if type firefox ; then
	    # If firefox is available, we start it with a new
	    # profile. This make sure that we do not reuse any
	    # running firefox instance, and a new instance is
	    # created.  When the users closes the firefox window
	    # then we know that we can delete the temp file.
	    wrkdir=$(mktemp -d)
	    trap "rm -rf $wrkdir" EXIT
	    markdown > $wrkdir/assist_doc.html
	    HOME=$wrkdir firefox -no-remote $wrkdir/assist_doc.html
	    rm -rf $wrkdir
	  else
	    local output=/tmp/md.$UID.html
	    rm -f $output
	    markdown > $output
	    xdg-open $output
	  fi
	  ;;
	*)
	  fatal "Invalid option"
	  ;;
      esac
  )
}

##
## inject
## ------
##
## Injects code into a ArchLinux initramfs install image that will
## launch the _ASSIST_ script automatically on boot
##
## Usage:
##
##        assist inject [source_img] [destination_img]
##
assist_inject() {
  [ $# -ne 2 ] && fatal "Usage: <src> <dst>"
  if [ $UID -ne 0 ] ; then
    echo "Faking root..."
    exec fakeroot -- "$0" inject "$1" "$2"
    fatal "fakeroot: failed"
  fi
  echo "ASSIST Injecting $ver"
  [ ! -r "$0" ] && fatal "Can not read script"
  WRKDIR=$(mktemp -d)
  trap "rm -rf $WRKDIR" EXIT
  echo -n "Unpacking initramfs image "
  xz -d < "$1" | ( cd $WRKDIR && cpio -id ) || fatal "Unpack failed"
  echo "Patching image"
  echo 'LATEHOOKS="$LATEHOOKS assist"' >> $WRKDIR/config
  (
    echo "#!/bin/sh"
    declare -f run_latehook
  ) > $WRKDIR/hooks/assist
  chmod 755  $WRKDIR/hooks/assist
  cat < "$0"  >$WRKDIR/assist.sh
  chmod 755 $WRKDIR/assist.sh
  echo -n "Repacking image "
  ( cd $WRKDIR ; find . | cpio -H newc -o ) | gzip -v9 > "$2"
}


######################################################################

# Script that is inserted into the initramfs image
run_latehook() {
  if [ ! -f /assist.sh ] ; then
    echo "=========================================================="
    echo "ASSIST injection failed!"
    echo "=========================================================="
  else
    echo "=========================================================="
    echo "Injecting ASSIST into boot process"
    echo "=========================================================="
    cp /assist.sh /new_root/assist.sh
    chmod 755 /new_root/assist.sh
    cat >/new_root/etc/profile.d/assist.sh <<EOF
#!/bin/sh
rm -f /etc/profile.d/assist.sh
/assist.sh
EOF
  fi
}

assist_ready_to_commit() {
  [ -n "$auto_continue" ] && return
  dlg --defaultno --yesno "Last chance to turn back!

Are you sure you want to bootstrap this system?

SYSNAME=$sysname
TARGET=$target ($autopart)
SOFTWARE=$sw_list
BOOTLOADER=$bootloader
TZ=$tz
LOCALE=$locale" 0 0 || aborted
}

assist_finalize() {
  [ -z "$auto_continue" ] \
      && dlg --yesno "Bootstrap completed.  You can reboot now.  Do you want to unmount filesystems?" 0 0 \
      || return
  umount_all /mnt
}


######################################################################
#
# The following are simple, useful support functions
#
######################################################################
fatal() {
  echo "$@" 1>&2
  exit 1
}
aborted() {
  fatal "Aborted by user"
}

dlg() (
    set +x
    exec 3>&1
    exec 1>&2
    exec 2>&3
    exec dialog --backtitle "ASSIST ($ver)" "$@"
)

EDITOR=
edit() {
  # let user choose preferred editor
  [ -z $EDITOR ] && EDITOR=$(dlg --menu "Select preferred editor" 0 0 0 vi '' nano '')
  [ -z "$EDITOR" ] && aborted
  $EDITOR "$@"
}

hwaddr() {
  ifconfig "$1" | grep ether | awk '{ print $2 }'
}

no_dft_gw() {
  return $(awk '$2 == "00000000" { print $1 }' < /proc/net/route | wc -l)
}

pause() {
  [ -n "$no_pause" ] && return
  local z
  if [ $# -eq 0 ] ; then
    echo -n "Press ENTER to continue: "
  else
    echo "$@"
  fi
  read z
}

find_discs() {
  local x
  for x in /sys/block/*
  do
    readlink $x | grep -q /virtual/ && continue
    [ $(basename $(readlink $x/device/driver)) != "sd" ] && continue
    basename $x
  done
}

nparts() {
 [ $(genfstab -p -U $1 | wc -l ) -eq 0 ] && return 1
 return 0
}

pick_netif() {
  if [ $# -eq 1 ] ; then
    echo $1
    return
  fi
  local ifx i
  for i in $*
  do
    ifx+=( $i "$(hwaddr $i)" )
  done
  i=$(dlg --menu "Select network interface" 0 0 0 "${ifx[@]}")
  [ -z "$i" ] && i="$1"
  echo $i
}

add_sw_dep() {
  if [ -z "$sw_deps" ] ; then
    sw_deps="$*"
  else
    sw_deps="$sw_deps $*"
  fi
}

umount_all() {
    local mnt="$1"
    umount $(awk '$2 ~ /^\'$mnt'/ { print $2 }' < /proc/mounts | sort -r)
    swapoff -a

}

######################################################################
# Some preparation code.  This makes it easier to deploy from web scripts
oIFS="$IFS"
[ -n "$url" ] && return	# Avoid src loops...
assist_main "$@"
exit $?

##
## Copyright
## =========
##
##    ASSIST <VER>  
##    Copyright (C) 2013 Alejandro Liu
##
##    This program is free software: you can redistribute it and/or modify
##    it under the terms of the GNU General Public License as published by
##    the Free Software Foundation, either version 2 of the License, or
##    (at your option) any later version.
##
##    This program is distributed in the hope that it will be useful,
##    but WITHOUT ANY WARRANTY; without even the implied warranty of
##    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
##    GNU General Public License for more details.
##
##    You should have received a copy of the GNU General Public License
##    along with this program.  If not, see <http://www.gnu.org/licenses/>.
##
