
ASSIST (0.3dev)
==============
_Arch System Software Installation Scripting Tool_

_ASSIST_ is a script utility used for new Arch Linux installs.

It aims to be a very simple installation script that essentially
follows what the install instructions say without trying to be too
smart about it.

It also is meant to be easy to deploy/inject into installations and
aims to be extensible enough that additional features can be added
and the installation be mostly automated.

_ASSIST_ does not try to handle all possible installation cases nor
tries to implement all the features available in the old AIF
scripts.

Using ASSIST
============

If used without arguments, _ASSIST_ will attempt to perform an
archlinux install.

It will do so in the following stages:

- `pre-config` : Usually configuration through command line paramenters
  entered as boot command options, arguments to _ASSIST_ or environment
  variables.
- `pre-input` : Some basic configuration that might need to happen *before*
  we have an available network
- `setup config` : Perform any (network based) configuration activities.
- `setup input` : Collect additional input on how the installation needs
  to be performed.
- `installation` : Performs the bulk of the install task.
- `Post input` : Perform some post installation activities

Invoking _ASSIST_
---------------

_ASSIST_ can be invoked to install Arch Linux in a number of ways


### From the net

You need to make sure that you have a working internet connection.
Enter the following:

       wget -O- https://raw.github.com/alejandroliu/assist/master/assist.sh | sh


### Injecting into INITRAMFS boot

       assist.sh inject _orig.img_ _new.img_

It will edit an initrd cpio image and will create a hook that will
arrange for _ASSIST_ to run automatically.

This is particularly useful for automated installation using a PXE
environment.


Running the installation
------------------------

### Pre-configuration

Initially _ASSIST_ will ask the user for some pre-configuration information

- Keyboard layout
- Network Setup

#### Keyboard Layout

For many countries and keyboard types appropriate keymaps are available
already, and a command like `loadkeys uk` might do what you want. More
available keymap files can be found in `/usr/share/kbd/keymaps/`
(you can omit the keymap path and file extension when using `loadkeys`).

_ASSIST_ will look in `/usr/share/kbd/keymaps/` and let you select a
Keymap from there.

#### Networking

Usually a DHCP service is already enabled for all available devices.  
Sometimes this may fail, or you need to configure either _wireless_
or _static IP_.


There are three (3) options for network configuration:

1. `dhcp` : for the case that `dhcpcd` failed to start.
2. `static` : To enter static IP addresses.
3. `wifi` : for configuring Wireless networks



### Set-up customization

Once we have a proper keyboard layout and a working network,
_ASSIST_ will attempt to customise your installation.

- hostname
- partitioning schema
- bootloader
- pacman mirrors
- software groups
- locale and timezone


#### Partitioning

_ASSIST_ has two (2) different partitioning modes:

1. `autopart` - mostly automated partitioning for a single drive
    configuration
2. `none` - assumes that the user created and mounted partitions already

##### autopart

Autopartitioning will let you select one drive (if there are more than
one).

_ASSIST_ will apply a basic partitioning schema on the selected disc:

- `/` : root partition (ext4, 15G)
- `/boot` : boot partition (ext2, 128M)
- `swap` : swap partition (2G)
- `/home` : will use the rest of the disc

While the mountpoints and filesystem types are fixed, _ASSIST_ will give
you an opportunity to change the sizes and/or remove partitions.

When changing partition sizes, entering a value of "`0`" wil cause
that partition to *not* be created.  While entering an _empty_ or
_blank_ size, will make that partition as large as possible.


##### none

This option assumes that the user already has prepared the installation
target and that it is mounted under `/mnt`.


#### Bootloader

In the spirit of keeping things simple, _ASSIST_ defaults to *SYSLINUX*`
for the bootloader.


#### Mirror lists

This lets you customize the pacman mirror list.

This copy of the mirrorlist will be installed on your new system by
pacstrap as well, so it's worth getting it right.

The following options are available:

- `edit`  
  Simply edit the mirrorlist using a text editor
- `country`  
  Will generate a mirror list based on your country.
- `none`  
  Simply use the existing mirrorlist.


When configuring by country, you will select a country and this will
in turn use the URL:

<https://www.archlinux.org/mirrorlist/?country=$country&protocol=ftp&protocol=http&ip_version=4&use_mirror_status=on>

To create an initial mirrorlist.  Then you may review and modify it.


### Software Selection

This will let you customise the initial software selection.  Note that
this is just a subset of all the software available in ArchLinux.
The idea is that this is enough software to bootstrap your system.
You can then later use `pacman` to add any additional software.


### Locale and timezone

This lets you specify the locale you want to use and the timezone
you are located in.


### Installation

After entering all the setup customisations, _ASSIST_ will perform the
installation.

Normally this would include:

- paritioning the target disc
- installing selected software
- creating the `fstab` file
- installing a bootloader
- configuring the system:
  - hostname
  - timezone
  - locale
- set-up a basic `dhcp` based `netcfg` profile
- create a initramfs file

This is a good time to take a coffee break.


### Post Install tasks


Once installation is completed you _ASSIST_ will run through final
customisation activities:

- change root password
- create users


#### Changing the root password

It is very important to secure your system with a strong password.
By default _ASSIST_ will prompt you to enter a new root password
when the installation finishes.


#### Creating users

It is important that you do not run your system as a root (adminstrative)
user.  So it is highly recommended to always create user accounts for
normal system usage.

At the end of the installation _ASSIST_ will let you create new users.


Automating _ASSIST_ installations
===============================

_ASSIST_ is designed to allow automated installs.  Most of the input
prompts in the installations can be given suitable defaults so that
they do not need to be entered by the user.

Configurable variables
----------------------

The following configuration variables are recognised:

- `kbd` : Keyboard layout to use
- `sysname` : System host name
- `autopart` : Automatic partition configuration
- `target` : Target disc to install to
- `mirrorlist` : file or url to use for initialising the pacman mirrorlist
- `sw_list` : list of software to install
- `bootloader` : Boot loader configuration
- `tz` : Time zone
- `locale` : System localisation

In addition, the following boolean variables control user interaction

- `auto_continue` : will skip some of the prompts
- `no_pause : will skip all `pause` prompts.

Finally, these additional variables configure certain aspects
of the installation:

- `kbd_platform` (`i386`): Used to determine the keymaps to show
- `dftkbd` (`us`): The default keyboard to offer the user
- `sw_mandatory` : The list of mandatory software packages to be shown
   during software selection.
- `sw_recommended` : The list of recommended packages
- `sw_suggested` : The list of suggested packages
- `sw_optional` : List of optional packages.
- `sw_deps` : Contains the list of software added by _ASSIST_ dependancies.

Defining configuration defaults
-------------------------------

Configuration defaults can be achieved through boot parameters,
command line argumets, environment variables or configuration
scripts.

### Kernel boot command line

_ASSIST_ will examine the kernel boot command line and look for
configuration parameters begining with `assist_`.  So if you want
to configure the `kbd` variable to `us` in the boot command line you
would enter:

    assist_kbd=us

Boolean variables can be specified as this:

    assist\_auto\_continue


### command line

_ASSIST_ can be invoked with command line parameters:

       assist setup [opts ...]

Because _ASSIST_ accepts multiple sub-commands, you must specify the
`setup` option (which is the default if no arguments are used).

The arguments after that are either boolean or key-value pairs specifying
the default options.  For example:

       assist setup kbd=us auto_continue


### Environment variable

_ASSIST_ will exammine the `ASSIST_ARGS` environment variable.  if
found, its contents would be interpreted in the same way as the
command line arguments


### Configuration files

You can also load defaults from configuration files. These are
specified from the boot prompt or the command line with:

       src=_path or url to config file_

(Note that unlike boot variables that need the `assist_` prefix,
configuration scripts only need `src` to be specified.)


The `src` entry may point to either a file or an URL.  The contents
of the `src` files are standard `bash` scripts that are sourced
by _ASSIST_.  This means that you not only can use it define defaults,
but can be used to define new additional functionality for _ASSIST_.


Keep in mind that even though you can use `src` to define defaults,
the command line settings and environment variables will always
take precendence over `src` settings or kernel boot parameters.


As mentioned earlier, `src` files are standard bash scripts.  You
can use it to add additional functionality to _ASSIST_.  Essentially
all of _ASSIST_ is modular and can be overriden by a `src` script
by simply defining a new function.

For convenience the following functions are defined:

- `assist_inst_pre`  
   By default it is empty, but is executed right at the beginning
   of the installation.
- `assist_inst_post`  
   Similarly, empty by default, but gets executed towards the
   end of the install.

You are encouraged to peek in the _ASSIST_ script to find out what
functions are defined so you can override them.


### Using configuration defaults

Configuration defaults can be entered interactively but normally it
is expected to be entered into the installation media or through
the DHCP server that drives a PXE boot install.


_ASSIST_ Installation Details
===========================

This section describes what _ASSIST_ does when performan an install.

Partitioning
------------

This is configured by `target` and `autopart` variables.
The function to override is `assist_inst_partition`.  Because
the bootloader is tightly integrated with the partitioning,
there are two additional override functions:

- `assist_inst_part1_$bootloader`
- `assist_inst_part2_$bootloader`

The default paritioning will create a GPT partioning table.
After that partitions will be formated (`mkswap` or `mkfs`) and
mounted automatically under `/mnt`.


Software installation
---------------------

This is configured by `sw_list` and `sw_deps` variables.
The function to override is `assist_inst_sw`.

Will run `pacstrap` to install the selected software.


System configuration
--------------------

The following configuration tasks happen after software install:

### fstab

Function to override `assist_inst_fstab`.

Create a new `fstab` file using `genfstab`

### bootloader

Function to override: `assist_inst_$bootloader`

#### syslinux

Will modify the `syslinux.cfg` file to point to the right `root`
device and also will add the `nomodeset` parameter if it was
specified when booting the installation media.


### hostname

Configured with `sysname` variable.
Function to override: `assist_inst_hostname`.

Will set the `hostname` for the newly installed system.

### Timezone

Configured with `tz` variable.
Function to override: `assist_inst_tz`.

Configure the local timezone for the system.

#### Locale

Configured with `kbd`, `locale` variables.
Function to override: `assist_inst_locale`.

Configures the keyboard layout in `/etc/vconsole.conf` and
the system locale in `/etc/locale.conf` and `/etc/locale.gen`.

#### Network

Function to override: `assist_inst_netcfg`.

Creates a basic `netcfg` profile for all the wired interfaces
found in the system.


### initramfs

Function to override: `assist_inst_mkinitcpio`.

Configures the initramfs contents.


Command-line
============

    assist {sub_cmd} [args]

Available sub commands:

- `inject` - Injects _ASSIST_ into a `initrd` image.
- `doc` - display documentation
- `setup` - Performs an ArchLinux install

The default sub-command if none is specified is `setup`.


Utility Sub Commands
====================

doc
---

Displays the on-line documentation for _ASSIST_

Usage:

       assist doc [options]

Options:

- `text` : plain text output
- `html` : HTML document
- `viewhtml` : Will show manual on a browser window.

inject
------

Injects code into a ArchLinux initramfs install image that will
launch the _ASSIST_ script automatically on boot

Usage:

       assist inject [source_img] [destination_img]


Copyright
=========

   ASSIST 0.3dev  
   Copyright (C) 2013 Alejandro Liu

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>.

