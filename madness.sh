#!/bin/sh

# Copyright (c) 2012, Iain H
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met: 
# 
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer. 
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution. 
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#
# Revision: 
#  - 1.0: Initial draft
#  - 1.1: Add automatic detection of network interface, more conplete rc.conf,
#         and install docs by default for man pages 

# TODO: 
#  - Persistent resolv.conf
#  - Automatic determination for disks
#  - Prompt user for hostname

#---------
# Variables to modify
#----------
DISKS="da0 da1"
SWAP_SIZE=1G
HOSTNAME="revo-vm"
#----------

echo -n "Determining network interface..."
NETIF=`/sbin/ifconfig -l -u | /usr/bin/sed -e 's/lo0//' -e 's/ //g'`

for disk in ${DISKS}; do
	NUMBER=$( echo ${disk} | tr -c -d '0-9' )
	gpart destroy -F ${disk}
	gpart create -s GPT ${disk}
	gpart add -t freebsd-boot -l bootcode${NUMBER} -s 128k ${disk}
	gpart add -t freebsd-zfs -l sys${NUMBER} ${disk}
        gpart add -t freebsd-swap -l swap${NUMBER} -s ${SWAP_SIZE} ${disk}
	gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 ${disk}
done

zpool create -f -o cachefile=/tmp/zpool.cache sys mirror /dev/gpt/sys*
zfs set mountpoint=none sys
zfs set checksum=fletcher4 sys
zfs set atime=off sys
zfs create sys/ROOT
zfs create -o mountpoint=/mnt sys/ROOT/default
zpool set bootfs=sys/ROOT/default sys

cd /usr/freebsd-dist/
for I in base.txz kernel.txz doc.txz; do
	tar --unlink -xvpJf ${I} -C /mnt
done

cp /tmp/zpool.cache /mnt/boot/zfs/
cat << EOF >> /mnt/boot/loader.conf
loader_logo="beastie"
zfs_load=YES
vfs.root.mountfrom="zfs:sys/ROOT/default"
EOF
cat << EOF >> /mnt/etc/rc.conf
zfs_enable=YES
background_fsck="NO"

ifconfig_${NETIF}="DHCP"
hostname="${HOSTNAME}"
sshd_enable="YES"
powerd_enable="YES"

# Postfix
postfix_enable="YES"
sendmail_enable="NO"
sendmail_submit_enable="NO"
sendmail_outbound_enable="NO"
sendmail_msp_queue_enable="NO"

# NTP
ntpdate_enable="YES"
ntpd_enable="YES"

EOF
:> /mnt/etc/fstab

if [ ${HOSTNAME} ]; then
cat << EOF >> /mnt/etc/hosts
127.0.0.1       ${HOSTNAME}
EOF
fi

cat << EOF >> /mnt/etc/resolv.conf
search spiralpoint.org
nameserver 216.104.96.23 
nameserver 216.104.98.223
EOF

# Set timezone to AST
/bin/cp /usr/share/zoneinfo/AST4ADT $DESTDIR/mnt/localtime

# Update the system using FreeBSD Update
echo "Running FreeBSD Update"
FREEBSD_UPDATE="/usr/sbin/freebsd-update"
# Fetch the updates
${FREEBSD_UPDATE} -b /mnt fetch >${OUTPUT_REDIR}

# Install the Downloaded FreeBSD Updates
${FREEBSD_UPDATE} -b /mnt install >${OUTPUT_REDIR}

zfs umount -a
zfs set mountpoint=legacy sys/ROOT/default

echo ""
read -p "Installation complete. Press enter to reboot" nothing

reboot
