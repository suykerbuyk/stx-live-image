lang en_US.UTF-8
keyboard us
timezone America/Denver --isUtc
auth --useshadow --enablemd5
selinux --disabled
firewall --disabled
part / --size 10240 --fstype ext4
services --enabled=network,sshd --disabled=NetworkManger
bootloader --append "inst.sshd=1 console=ttyS0,115200n8 SALT_MASTER=stx-prvsnr"

# Root password
rootpw Xyratex --plaintext

repo --name=base      --baseurl=http://stx-prvsnr/vendor/centos/7.5.1804/ --excludepkgs=grubby
repo --name=epel      --baseurl=http://stx-prvsnr/vendor/centos/epel/ --excludepkgs=grubby
repo --name=salt      --baseurl=http://stx-prvsnr/vendor/salt/2018.3.2/ --excludepkgs=grubby
repo --name=grubby    --baseurl=http://vault.centos.org/7.0.1406/os/x86_64/ --includepkgs=grubby

%packages --nobase --excludedocs
@core
OpenIPMI
epel-release
freeipmi
ipmitool
util-linux
lvm2
mdadm
nfs-utils
openssh
openssh-clients
openssh-server
openssl
python2-pip
rsync
salt-minion
salt-ssh
traceroute
nmap
net-tools
wget
-alsa-*
-btrfs-progs*
-ivtv*
-libertas*
-iwl*firmware
-postfix
# for UEFI/Secureboot support
grub2
grub2-efi
efibootmgr
shim-x64



%end

%post
# FIXME: it'd be better to get this installed from a package
cat > /etc/rc.d/init.d/livesys << EOF
#!/bin/bash
#
# live: Init script for live image
#
# chkconfig: 345 00 99
# description: Init script for live image.
### BEGIN INIT INFO
# X-Start-Before: display-manager
### END INIT INFO

. /etc/init.d/functions

if ! strstr "\`cat /proc/cmdline\`" rd.live.image || [ "\$1" != "start" ]; then
    exit 0
fi

if [ -e /.liveimg-configured ] ; then
    configdone=1
fi

exists() {
    which \$1 >/dev/null 2>&1 || return
    \$*
}

# Make sure we don't mangle the hardware clock on shutdown
ln -sf /dev/null /etc/systemd/system/hwclock-save.service

livedir="LiveOS"
for arg in \`cat /proc/cmdline\` ; do
  if [ "\${arg##rd.live.dir=}" != "\${arg}" ]; then
    livedir=\${arg##rd.live.dir=}
    return
  fi
  if [ "\${arg##live_dir=}" != "\${arg}" ]; then
    livedir=\${arg##live_dir=}
    return
  fi
done

# enable swaps unless requested otherwise
swaps=\`blkid -t TYPE=swap -o device\`
if ! strstr "\`cat /proc/cmdline\`" noswap && [ -n "\$swaps" ] ; then
  for s in \$swaps ; do
    action "Enabling swap partition \$s" swapon \$s
  done
fi
if ! strstr "\`cat /proc/cmdline\`" noswap && [ -f /run/initramfs/live/\${livedir}/swap.img ] ; then
  action "Enabling swap file" swapon /run/initramfs/live/\${livedir}/swap.img
fi

mountPersistentHome() {
  # support label/uuid
  if [ "\${homedev##LABEL=}" != "\${homedev}" -o "\${homedev##UUID=}" != "\${homedev}" ]; then
    homedev=\`/sbin/blkid -o device -t "\$homedev"\`
  fi

  # if we're given a file rather than a blockdev, loopback it
  if [ "\${homedev##mtd}" != "\${homedev}" ]; then
    # mtd devs don't have a block device but get magic-mounted with -t jffs2
    mountopts="-t jffs2"
  elif [ ! -b "\$homedev" ]; then
    loopdev=\`losetup -f\`
    if [ "\${homedev##/run/initramfs/live}" != "\${homedev}" ]; then
      action "Remounting live store r/w" mount -o remount,rw /run/initramfs/live
    fi
    losetup \$loopdev \$homedev
    homedev=\$loopdev
  fi

  # if it's encrypted, we need to unlock it
  if [ "\$(/sbin/blkid -s TYPE -o value \$homedev 2>/dev/null)" = "crypto_LUKS" ]; then
    echo
    echo "Setting up encrypted /home device"
    plymouth ask-for-password --command="cryptsetup luksOpen \$homedev EncHome"
    homedev=/dev/mapper/EncHome
  fi

  # and finally do the mount
  mount \$mountopts \$homedev /home
  # if we have /home under what's passed for persistent home, then
  # we should make that the real /home.  useful for mtd device on olpc
  if [ -d /home/home ]; then mount --bind /home/home /home ; fi
  [ -x /sbin/restorecon ] && /sbin/restorecon /home
  if [ -d /home/liveuser ]; then USERADDARGS="-M" ; fi
}

findPersistentHome() {
  for arg in \`cat /proc/cmdline\` ; do
    if [ "\${arg##persistenthome=}" != "\${arg}" ]; then
      homedev=\${arg##persistenthome=}
      return
    fi
  done
}

if strstr "\`cat /proc/cmdline\`" persistenthome= ; then
  findPersistentHome
elif [ -e /run/initramfs/live/\${livedir}/home.img ]; then
  homedev=/run/initramfs/live/\${livedir}/home.img
fi

# if we have a persistent /home, then we want to go ahead and mount it
if ! strstr "\`cat /proc/cmdline\`" nopersistenthome && [ -n "\$homedev" ] ; then
  action "Mounting persistent /home" mountPersistentHome
fi

# make it so that we don't do writing to the overlay for things which
# are just tmpdirs/caches
mount -t tmpfs -o mode=0755 varcacheyum /var/cache/yum
mount -t tmpfs vartmp /var/tmp
[ -x /sbin/restorecon ] && /sbin/restorecon /var/cache/yum /var/tmp >/dev/null 2>&1

if [ -n "\$configdone" ]; then
  exit 0
fi

# add live user with no passwd
action "Adding live user" useradd \$USERADDARGS -c "Live System User" liveuser
passwd -d liveuser > /dev/null
usermod -aG wheel liveuser > /dev/null

# Remove root password lock
passwd -k root > /dev/null

mkdir /root/.ssh/
cat > /root/.ssh/authorized_keys << SSH_EOF
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDG19XV+hyNxBrTxxGyBBPfox4/4P9WNStlHW99SPnfRR0Zx6jWc9sYG/ushdKJUV+KBAKdoXGkSwP23JcuhVLwgzwrxNYKezb2elgrWlVhUexkZrFfQab8wktOxAsiiemNr4H0FFXWzwWSy7EuYkHK9hrdaMTzQEGT8UMyj8slzazsi5suF5bcwTTd3WP8fkwYqHclwjOcEg7I57cD2jaxkY2HBEwAzwnxdquvXqNXVvRozHvPIAFNii52XyDjxbJay0Kw8A5BSE6oX7cpvUL0rEtaHVHHeHG6zUNN8Qi8iBlnsDtOzTkrK5pJ0ZwW5zV1a7ILoQQOPSa3dmbg8LDJ pythia
SSH_EOF
cat > /root/.ssh/id_rsa << SSH_EOF
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAxtfV1focjcQa08cRsgQT36MeP+D/VjUrZR1vfUj530UdGceo
1nPbGBv7rIXSiVFfigQCnaFxpEsD9tyXLoVS8IM8K8TWCns29npYK1pVYVHsZGax
X0Gm/MJLTsQLIonpja+B9BRV1s8FksuxLmJByvYa3WjE80BBk/FDMo/LJc2s7Iub
LheW3ME03d1j/H5MGKh3JcIznBIOyOe3A9o2sZGNhwRMAM8J8Xarr16jV1b0aMx7
zyABTYoudl8g48WyWstCsPAOQUhOqF+3Kb1C9KxLWh1Rx3hxus1DTfEIvIgZZ7A7
Ts05KyuaSdGcFuc1dWuyC6EEDj0mt3Zm4PCwyQIDAQABAoIBAFbvVJlp8YP1wjjn
JxBqgfnbykTpbRlWw7NArFbdSgnYoMF9ro6cNqUSzvT9yS+qORgRasdaJ2JKPeB3
T03SkpF+/xavx1jrx/r5QIUryHp1I+I9l7zq6kRF+kDkq22dWFRO8IUzQthYyLoG
fl+mK9e9w78bqEglxsYUzGlVvt62iT1SMtqdZDUQVgjlUVO6L0OWHjsqFt/Lql3a
J48dnaccUot+rn0ryaBABfemCtv1Q5nhHVyDzgs+nmn90mwTM1l1BuzRG/rnNSPO
wqfE7CN9hv6M8a41RTt38/+q7hRlnM/IIPX60darpwPp7BMVkWj8GrOdaDoZECGP
fboc1gECgYEA6p+Vu25Zyu1kugxTBMj0MCe+8aLptwb4RkIcME8/y+9Ih/7g6DQS
65DOU8aPIoN/iYX25NDFJLNWbvbW61WNbDtq+2b0Y5IKlIJm4bVKXTTykP1wAz07
DRL6YfUbytQ+0cFAu3IIxYdhiiATdXw4qq4tJRCLzKWvC5QzUMzadcECgYEA2PWz
yLVm6QfT9bglQhw3RMPKIuPBVkgCVC1NcGAyjj2AREMymv1KlLk4Kz1pQuTDJitr
sjGHvBSSa8SBFa/n/mP9V+rgBnWjhr+A0lK0/uML6XtZghTr44lfk5NdDGFsP2Qi
Gi2OFkLT67JDKukcqgtI6uKDFdZG6fc1npC3zQkCgYEAh0Rqdx0v96bWI81nL6ML
5ZeEppteU39ZNGh5CAEortLN5lo0IKulHNrnmbUoYKWfqhHqPhF/F6Gte1wknJk+
Z9/51eeNjrpsDyL/XbG/pe0YzC7RnYx3txnx8Pf3hgDIFvZr86XTGM7slU3Y6iss
IHs629umPd5oBSz0SOlSKgECgYEAyEPUVfoMKiINpwz5Z1LAOXs4hIgTGF+Ttruy
dX52bBGc6mXUunf/ddSaYl9nYFXlRMBjwrIxhoy+szdJqAkdbhZB7ftiGtRPw7vV
X070vyo4/qXbc1V4gCl3zbMC+sCauNDnIZ7XPvkkwLVlhqBy0wtjnVzEf02xW5nT
JrCS2HECgYAWPtknA0Wxi6A9kukxqd9kr0Ge9u3fS8qdJ3qWlkPg2KkgXUN6taxV
tuvOQJAOWsNUl93v/rot3Lh4SbyqWQaj8gACVA2bFEPD5e5cffd/EEGbBTpsClmz
zDPaFSIrXso/hFxrhowJFhTzJwNMBwvM0LdIGMk88aAj9zdCzRF4mg==
-----END RSA PRIVATE KEY-----
SSH_EOF
cat > /root/.ssh/id_rsa.pub << SSH_EOF

ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDG19XV+hyNxBrTxxGyBBPfox4/4P9WNStlHW99SPnfRR0Zx6jWc9sYG/ushdKJUV+KBAKdoXGkSwP23JcuhVLwgzwrxNYKezb2elgrWlVhUexkZrFfQab8wktOxAsiiemNr4H0FFXWzwWSy7EuYkHK9hrdaMTzQEGT8UMyj8slzazsi5suF5bcwTTd3WP8fkwYqHclwjOcEg7I57cD2jaxkY2HBEwAzwnxdquvXqNXVvRozHvPIAFNii52XyDjxbJay0Kw8A5BSE6oX7cpvUL0rEtaHVHHeHG6zUNN8Qi8iBlnsDtOzTkrK5pJ0ZwW5zV1a7ILoQQOPSa3dmbg8LDJ pythia
SSH_EOF

find /root/.ssh/ -type f | xargs chmod 0600
chmod 0700 /root/.ssh

# Insert common precooked minion keys
mkdir -p /etc/salt/pki/minion
chmod 0700 /etc/salt/pki/minion

cat >/etc/salt/pki/minion/minion.pem << MINION_PRIVATE_EOF 
-----BEGIN RSA PRIVATE KEY-----
MIIEogIBAAKCAQEAtiZSSnmiYYCsK7U+Vr/c8n0H8hzQDaZaEV/jGz1dyz7DOiNN
BU1Ku6zfoxWyUQNlds9ZdK+XBfT87LuR9xVxGhz8Hl2mTaRfP9Vqk4EeAv86VAzI
6etMKeOvBarTuK16xDHowgcnjGoeHzFVkfY1TSL/WbSe2IcLCezaDm4NqH5X5Bqx
eiPDbrca/7DV7xGqgXsxV7ObnNpaKa1M+eXz8Zb9umqiVTm4R5DrdHQApFWqHmJt
tZSfg/DpBoCvjpzH6e3Ms2UgDpN1rChQqWkhw7dR9iU9rE5FpWa9FTvODZN/LcTg
nU0baWCVzyIdOuFGa+5e8Hj1KfJTNEVjUsWqlQIDAQABAoIBABuXLGnZiM4qFmo8
duffAhG8/KIg2SboJsZw9s6eegGaTSoWRMljzskkw29JjwwUbp8Tg2JYYpDlbhZR
xyddGReygkH7P4CNQFxD8HPNYAVmMaifkyNTn+LMeStrl8xmgq0LPk19lfD/9fYV
m/eTCrnXbkRhRppXwkVLmjALXYhC8ZE9Gb5DDzcvKWg0n2VwmBNpFEzxOtineIx3
ia3ICWVpMuxc5oFhppf4F6sX1uOhWhDlsb/3zdXHTVbk5w5qr1p4DpdzhLzaD17x
4ElmyMhDY4LAw0KJFT3UnVqM5R/2pzG3WEn3OYPG6fAJh8w0B5nodZWecYbZ4lxe
8UHiqjUCgYEA2+xN961WPDWG6dlUlSWBCTGfkmqeya0F0fUaOIgUUk+pIKYq+qTa
o9/UrkUlRGR3zjOPUCLGsbns06w6wO4w6/r31H6fNHe0E2GQg29ist45QpiBYGzO
JOD41jHtaB/jPyo763fR/cNLNtqDw+WYimxeLisI7AVZOLiLN8c/P78CgYEA1Ae4
OX59L3xHkRKbFWJVt2mQlZ2w/8qVcuFNUaHEPiFBluUPiZzR48CpS0KpVHcmgyxp
DrpmoE5iLoRT2+wDbDBgAmEgRwZi311B3oX+2MGKCBb/v1oNthVh4TxsjZGUHGqf
XhIgYV5hjok//nZSxWMG6CzfpL3fcsaVLG0faqsCgYBIeEoI/9mW5Zybmr5Al6c5
vFx1ByVkF9v/H+GQF2d66D03QQqQpZpWvf97ndV2ABVqoZrsMUmAb2AXMH377YG5
gW4BW+hihb+VU2UnqqC/iHMd+ttHRxN3G5tkGfe9hCSCQAyWv1k3Yg969+7LsvDd
THCMjinWfLy18DoQG1xASQKBgG7Qigwie7LxtUWw/7SxbDMrzRElFXjanDkqX4qm
jTYbk3gVx4UYnOn3q4NWF8G5dDtiXpX//dsSnGXLazippTBKKCOWN5RnVg1/ZAm0
5njKziVkP832duwPSNS7C9EBoPMpFpnHx3ycI0inmvaXSLM5CkcWDNzBD6Og/h31
+lF5AoGAXrYSUt9aK8O63oetFGiqeyQ8En6J9+J4WMbs51LlAlJoLKpL9D0CMqO5
ZfNPifzz+uK8N5eupQN4M1PVwRHFzEN3mtSI/fSeF77ZFH3eZAn0F6jFozZAN/BC
4qV8N/eu0faHHLNMFVRowl7Y651dzatdpqxSLDVVD3aA5M4x/KE=
-----END RSA PRIVATE KEY-----
MINION_PRIVATE_EOF
chmod 0400 /etc/salt/pki/minion/minion.pem

cat >/etc/salt/pki/minion/minion.pub << MINION_PUBLIC_EOF
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtiZSSnmiYYCsK7U+Vr/c
8n0H8hzQDaZaEV/jGz1dyz7DOiNNBU1Ku6zfoxWyUQNlds9ZdK+XBfT87LuR9xVx
Ghz8Hl2mTaRfP9Vqk4EeAv86VAzI6etMKeOvBarTuK16xDHowgcnjGoeHzFVkfY1
TSL/WbSe2IcLCezaDm4NqH5X5BqxeiPDbrca/7DV7xGqgXsxV7ObnNpaKa1M+eXz
8Zb9umqiVTm4R5DrdHQApFWqHmJttZSfg/DpBoCvjpzH6e3Ms2UgDpN1rChQqWkh
w7dR9iU9rE5FpWa9FTvODZN/LcTgnU0baWCVzyIdOuFGa+5e8Hj1KfJTNEVjUsWq
lQIDAQAB
-----END PUBLIC KEY-----
MINION_PUBLIC_EOF
chmod 0644 /etc/salt/pki/minion/minion.pub

# turn off firstboot for livecd boots
systemctl --no-reload disable firstboot-text.service 2> /dev/null || :
systemctl --no-reload disable firstboot-graphical.service 2> /dev/null || :
systemctl stop firstboot-text.service 2> /dev/null || :
systemctl stop firstboot-graphical.service 2> /dev/null || :

# don't use prelink on a running live image
sed -i 's/PRELINKING=yes/PRELINKING=no/' /etc/sysconfig/prelink &>/dev/null || :

# turn off mdmonitor by default
systemctl --no-reload disable mdmonitor.service 2> /dev/null || :
systemctl --no-reload disable mdmonitor-takeover.service 2> /dev/null || :
systemctl stop mdmonitor.service 2> /dev/null || :
systemctl stop mdmonitor-takeover.service 2> /dev/null || :


# don't start cron/at as they tend to spawn things which are
# disk intensive that are painful on a live image
systemctl --no-reload disable crond.service 2> /dev/null || :
systemctl --no-reload disable atd.service 2> /dev/null || :
systemctl stop crond.service 2> /dev/null || :
systemctl stop atd.service 2> /dev/null || :

# disable kdump service
systemctl --no-reload disable kdump.service 2> /dev/null || :
systemctl stop kdump.service 2> /dev/null || :

# disable tuned.service
systemctl --no-reload disable tuned.service 2> /dev/null || :
systemctl stop tuned.service 2> /dev/null || :

# Mark things as configured
touch /.liveimg-configured

# add static hostname to work around xauth bug
# https://bugzilla.redhat.com/show_bug.cgi?id=679486
echo "localhost" > /etc/hostname

# Fixing the lang install issue when other lang than English is selected . See http://bugs.centos.org/view.php?id=7217
/usr/bin/cp /usr/lib/python2.7/site-packages/blivet/size.py /usr/lib/python2.7/site-packages/blivet/size.py.orig
/usr/bin/sed -i "s#return self.humanReadable()#return self.humanReadable().encode('utf-8')#g" /usr/lib/python2.7/site-packages/blivet/size.py

EOF

# bah, hal starts way too late
cat > /etc/rc.d/init.d/livesys-late << EOF
#!/bin/bash
#
# live: Late init script for live image
#
# chkconfig: 345 99 01
# description: Late init script for live image.

. /etc/init.d/functions

if ! strstr "\`cat /proc/cmdline\`" rd.live.image || [ "\$1" != "start" ] || [ -e /.liveimg-late-configured ] ; then
    exit 0
fi

exists() {
    which \$1 >/dev/null 2>&1 || return
    \$*
}

touch /.liveimg-late-configured

# enable and configure salt-minion
for i in \$(cat /proc/cmdline)
do
  case \$i in
     SALT_MASTER=* | salt_master=*)
     salt_master="\${i#*=}"
     sed -i "s/^#* *master:.*/master: \$salt_master/g" /etc/salt/minion || break
     ;;
  esac
done

# read some variables out of /proc/cmdline
for o in \`cat /proc/cmdline\` ; do
    case \$o in
    ks=*)
        ks="--kickstart=\${o#ks=}"
        ;;
    xdriver=*)
        xdriver="\${o#xdriver=}"
        ;;
    esac
done

# if liveinst or textinst is given, start anaconda
if strstr "\`cat /proc/cmdline\`" liveinst ; then
   plymouth --quit
   /usr/sbin/liveinst \$ks
fi
if strstr "\`cat /proc/cmdline\`" textinst ; then
   plymouth --quit
   /usr/sbin/liveinst --text \$ks
fi

EOF

chmod 755 /etc/rc.d/init.d/livesys
/sbin/restorecon /etc/rc.d/init.d/livesys
/sbin/chkconfig --add livesys

chmod 755 /etc/rc.d/init.d/livesys-late
/sbin/restorecon /etc/rc.d/init.d/livesys-late
/sbin/chkconfig --add livesys-late

# enable tmpfs for /tmp
systemctl enable tmp.mount
systemctl enable salt-minion

#pip install --upgrade pip
#pip install pyghmi

# work around for poor key import UI in PackageKit
rm -f /var/lib/rpm/__db*
releasever=$(rpm -q --qf '%{version}\n' --whatprovides system-release)
basearch=$(uname -i)
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-*
echo "Packages within this LiveCD (with version)"
rpm -qa | sort
echo "Packages within this LiveCD"
rpm -qa --qf "%{name}\n" | sort
# Note that running rpm recreates the rpm db files which aren't needed or wanted
rm -f /var/lib/rpm/__db*

# save a little bit of space at least...
rm -f /boot/initramfs*
# make sure there aren't core files lying around
rm -f /core*

# convince readahead not to collect
# FIXME: for systemd

cat >> /etc/rc.d/init.d/livesys << EOF

# disable updates plugin
cat >> /usr/share/glib-2.0/schemas/org.gnome.settings-daemon.plugins.updates.gschema.override << FOE
[org.gnome.settings-daemon.plugins.updates]
active=false
FOE


# Turn off PackageKit-command-not-found while uninstalled
if [ -f /etc/PackageKit/CommandNotFound.conf ]; then
  sed -i -e 's/^SoftwareSourceSearch=true/SoftwareSourceSearch=false/' /etc/PackageKit/CommandNotFound.conf
fi

# make sure to set the right permissions and selinux contexts
chown -R liveuser:liveuser /home/liveuser/
restorecon -R /home/liveuser/

# Fixing default locale to us - does not work for SL7.1
#localectl set-keymap us
#localectl set-x11-keymap us
EOF

# rebuild schema cache with any overrides we installed
glib-compile-schemas /usr/share/glib-2.0/schemas


%end
