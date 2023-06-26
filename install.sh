#!/bin/bash

###############################################################################
#
# Copyright 2022 NVIDIA Corporation
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
# FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
###############################################################################

PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/opt/mellanox/scripts"
CHROOT_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

fspath=$(readlink -f `dirname $0`)
rshimlog=`which bfrshlog 2> /dev/null`
distro="Mariner"
NIC_FW_UPDATE_DONE=0

log()
{
	msg="[$(date +%H:%M:%S)] $*"
	echo "$msg" > /dev/ttyAMA0
	echo "$msg" > /dev/hvc0
	if [ -n "$rshimlog" ]; then
		$rshimlog "$*"
	fi
}

fw_update()
{
	FW_UPDATER=/opt/mellanox/mlnx-fw-updater/mlnx_fw_updater.pl
	FW_DIR=/opt/mellanox/mlnx-fw-updater/firmware/

	if [[ -x /mnt/${FW_UPDATER} && -d /mnt/${FW_DIR} ]]; then
		log "INFO: Updating NIC firmware..."
		chroot /mnt ${FW_UPDATER} \
			--force-fw-update \
			--fw-dir ${FW_DIR}
		if [ $? -eq 0 ]; then
			log "INFO: NIC firmware update done"
		else
			log "INFO: NIC firmware update failed"
		fi
	else
		log "WARNING: NIC Firmware files were not found"
	fi
}

fw_reset()
{
	mst start > /dev/null 2>&1 || true
	chroot /mnt /sbin/mlnx_bf_configure > /dev/null 2>&1

	MLXFWRESET_TIMEOUT=${MLXFWRESET_TIMEOUT:-180}
	SECONDS=0
	while ! (chroot /mnt mlxfwreset -d /dev/mst/mt*_pciconf0 q 2>&1 | grep -w "Driver is the owner" | grep -qw "\-Supported")
	do
		if [ $SECONDS -gt $MLXFWRESET_TIMEOUT ]; then
			log "INFO: NIC Firmware reset is not supported. Host power cycle is required"
			return
		fi
		sleep 1
	done

	log "INFO: Running NIC Firmware reset"
	if [ "X$mode" == "Xmanufacturing" ]; then
		log "INFO: Rebooting..."
	fi
	# Wait for these messages to be pulled by the rshim service
	# as mlxfwreset will restart the DPU
	sleep 3

	msg=`chroot /mnt mlxfwreset -d /dev/mst/mt*_pciconf0 -y -l 3 --sync 1 r 2>&1`
	if [ $? -ne 0 ]; then
		log "INFO: NIC Firmware reset failed"
		log "INFO: $msg"
	else
		log "INFO: NIC Firmware reset done"
	fi
}

bind_partitions()
{
	mount --bind /proc /mnt/proc
	mount --bind /dev /mnt/dev
	mount --bind /sys /mnt/sys
}

unmount_partitions()
{
	umount /mnt/sys/fs/fuse/connections > /dev/null 2>&1 || true
	umount /mnt/sys > /dev/null 2>&1
	umount /mnt/dev > /dev/null 2>&1
	umount /mnt/proc > /dev/null 2>&1
	umount /mnt/boot/efi > /dev/null 2>&1
	umount /mnt > /dev/null 2>&1
}

#
# Set the Hardware Clock from the System Clock
#

hwclock -w

#
# Check auto configuration passed from boot-fifo
#
boot_fifo_path="/sys/bus/platform/devices/MLNXBF04:00/bootfifo"
if [ -e "${boot_fifo_path}" ]; then
	cfg_file=$(mktemp)
	# Get 16KB assuming it's big enough to hold the config file.
	dd if=${boot_fifo_path} of=${cfg_file} bs=4096 count=4

	#
	# Check the .xz signature {0xFD, '7', 'z', 'X', 'Z', 0x00} and extract the
	# config file from it. Then start decompression in the background.
	#
	offset=$(strings -a -t d ${cfg_file} | grep -m 1 "7zXZ" | awk '{print $1}')
	if [ -s "${cfg_file}" -a ."${offset}" != ."1" ]; then
		log "INFO: Found bf.cfg"
		cat ${cfg_file} | tr -d '\0' > /etc/bf.cfg
	fi
	rm -f $cfg_file
fi

#
# Check PXE installation
#
if [ ! -e /tmp/bfpxe.done ]; then touch /tmp/bfpxe.done; bfpxe; fi

if [ -e /etc/bf.cfg ]; then
	if ( bash -n /etc/bf.cfg ); then
		. /etc/bf.cfg
	else
		log "INFO: Invalid bf.cfg"
	fi
fi

if [ "X${DEBUG}" == "Xyes" ]; then
	log_output=/dev/kmsg
	if [ -n "$log_output" ]; then
		exec >$log_output 2>&1
		unset log_output
	fi
fi

function_exists()
{
	declare -f -F "$1" > /dev/null
	return $?
}

DHCP_CLASS_ID=${PXE_DHCP_CLASS_ID:-""}
DHCP_CLASS_ID_OOB=${DHCP_CLASS_ID_OOB:-"NVIDIA/BF/OOB"}
DHCP_CLASS_ID_DP=${DHCP_CLASS_ID_DP:-"NVIDIA/BF/DP"}
FACTORY_DEFAULT_DHCP_BEHAVIOR=${FACTORY_DEFAULT_DHCP_BEHAVIOR:-"true"}

if [ "${FACTORY_DEFAULT_DHCP_BEHAVIOR}" == "true" ]; then
	# Set factory defaults
	DHCP_CLASS_ID="NVIDIA/BF/PXE"
	DHCP_CLASS_ID_OOB="NVIDIA/BF/OOB"
	DHCP_CLASS_ID_DP="NVIDIA/BF/DP"
fi

log "INFO: $distro installation started"

# Create the Mariner partitions.
default_device=/dev/mmcblk0
if [ -b /dev/nvme0n1 ]; then
    default_device=/dev/nvme0n1
fi
device=${device:-"$default_device"}

# We cannot use wait-for-root as it expects the device to contain a
# known filesystem, which might not be the case here.
while [ ! -b $device ]; do
    printf "Waiting for %s to be ready\n" "$device"
    sleep 1
done

# Flash image
bs=512
reserved=34
boot_size_megs=50
mega=$((2**20))
boot_size_bytes=$(($boot_size_megs * $mega))

disk_sectors=`fdisk -l $device | grep "Disk $device:" | awk '{print $7}'`
disk_end=$((disk_sectors - reserved))

boot_start=2048
boot_size=$(($boot_size_bytes/$bs))
root_start=$((2048 + $boot_size))
root_end=$disk_end
root_size=$(($root_end - $root_start + 1))

dd if=/dev/zero of="$device" bs="$bs" count=1

sfdisk -f "$device" << EOF
label: gpt
label-id: A2DF9E70-6329-4679-9C1F-1DAF38AE25AE
device: ${device}
unit: sectors
first-lba: $reserved
last-lba: $disk_end

${device}p1 : start=$boot_start, size=$boot_size, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, uuid=CEAEF8AC-B559-4D83-ACB1-A4F45B26E7F0, name="EFI System", bootable
${device}p2 : start=$root_start ,size=$root_size, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, uuid=F093FF4B-CC26-408F-81F5-FF2DD6AE139F, name="writable"
EOF

sync

# Refresh partition table
sleep 1
blockdev --rereadpt ${device} > /dev/null 2>&1

if function_exists bfb_pre_install; then
	log "INFO: Running bfb_pre_install from bf.cfg"
	bfb_pre_install
fi

# Generate some entropy
mke2fs  ${device}p2 >> /dev/null

mkdosfs ${device}p1 -n "system-boot"
mkfs.ext4 -F ${device}p2 -L "writable"

fsck.vfat -a ${device}p1

mkdir -p /mnt
mount -t ext4 ${device}p2 /mnt
mkdir -p /mnt/boot/efi
mount -t vfat ${device}p1 /mnt/boot/efi

echo "Extracting /..."
export EXTRACT_UNSAFE_SYMLINKS=1
tar Jxf $fspath/image.tar.xz --warning=no-timestamp -C /mnt
sync

cat > /mnt/etc/fstab << EOF
LABEL=writable / ext4 defaults 0 1
LABEL=system-boot  /boot/efi       vfat    umask=0077      0       2
EOF

memtotal=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
if [ $memtotal -gt 16000000 ]; then
	sed -i -r -e "s/(net.netfilter.nf_conntrack_max).*/\1 = 1000000/" /mnt/usr/lib/sysctl.d/90-bluefield.conf
fi

bind_partitions

UUID=`lsblk -o UUID,LABEL | grep writable | awk '{print $1}'`
mkdir -p /mnt/boot/efi/boot/grub2 /mnt/boot/grub2
cat > /mnt/boot/efi/boot/grub2/grub.cfg << EOF
search -n -u $UUID -s

set bootprefix=/boot
set prefix=\$bootprefix/grub2/
configfile \$prefix/grub.cfg
EOF
if (hexdump -C /sys/firmware/acpi/tables/SSDT* | grep -q MLNXBF33); then
    # BlueField-3
    sed -i -e "s/0x01000000/0x13010000/g" /mnt/etc/default/grub
fi
chroot /mnt env PATH=$CHROOT_PATH /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg
chroot /mnt env PATH=$CHROOT_PATH /usr/sbin/grub2-set-default 0

vmlinuz=`cd /mnt/boot; /bin/ls -1 vmlinuz-* | tail -1`
initrd=`cd /mnt/boot; /bin/ls -1 initramfs-*img | tail -1 | sed -e "s/.old-dkms//"`
ln -snf $vmlinuz /mnt/boot/vmlinuz
ln -snf $initrd /mnt/boot/initramfs.img


chroot /mnt /usr/sbin/adduser -u 1000 -U --create-home -p '$1$n8sefSKr$GkGqw/uwOsWazSSG5.LwK.' mariner
echo "mariner ALL=(ALL) NOPASSWD:ALL" >> /mnt/etc/sudoers.d/90-bf-users

if [ `wc -l /mnt/etc/hostname | cut -d ' ' -f 1` -eq 0 ]; then
	echo "localhost" > /mnt/etc/hostname
fi

cat > /mnt/etc/resolv.conf << EOF
nameserver 192.168.100.1
EOF

echo "PasswordAuthentication yes" >> /mnt/etc/ssh/sshd_config
echo "PermitRootLogin yes" >> /mnt/etc/ssh/sshd_config
sed -i '0,/PermitRootLogin/{/PermitRootLogin/d;}' /mnt/etc/ssh/sshd_config

chroot /mnt /bin/systemctl enable serial-getty@ttyAMA0.service
chroot /mnt /bin/systemctl enable serial-getty@ttyAMA1.service
chroot /mnt /bin/systemctl enable serial-getty@hvc0.service
chroot /mnt /bin/systemctl enable openvswitch.service

if [ -x /usr/bin/uuidgen ]; then
	UUIDGEN=/usr/bin/uuidgen
else
	UUIDGEN=/mnt/usr/bin/uuidgen
fi

p0m0_uuid=`$UUIDGEN`
p1m0_uuid=`$UUIDGEN`
p0m0_mac=`echo ${p0m0_uuid} | sed -e 's/-//;s/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/02:\1:\2:\3:\4:\5/'`
p1m0_mac=`echo ${p1m0_uuid} | sed -e 's/-//;s/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/02:\1:\2:\3:\4:\5/'`

pciids=`lspci -nD 2> /dev/null | grep 15b3:a2d[26c] | awk '{print $1}'`

mkdir -p /mnt/etc/mellanox
echo > /mnt/etc/mellanox/mlnx-sf.conf

i=0
for pciid in $pciids
do
	uuid_iname=p${i}m0_uuid
	mac_iname=p${i}m0_mac
cat >> /mnt/etc/mellanox/mlnx-sf.conf << EOF
/sbin/mlnx-sf --action create --device $pciid --sfnum 0 --hwaddr ${!mac_iname}
EOF
	let i=i+1
done

# Update HW-dependant files
if (lspci -n -d 15b3: | grep -wq 'a2d2'); then
	# BlueField-1
	ln -snf snap_rpc_init_bf1.conf /mnt/etc/mlnx_snap/snap_rpc_init.conf
	# OOB interface does not exist on BlueField-1
	/bin/rm -f /mnt/etc/sysconfig/network-scripts/ifcfg-oob_net0
elif (lspci -n -d 15b3: | grep -wq 'a2d6'); then
	# BlueField-2
	ln -snf snap_rpc_init_bf2.conf /mnt/etc/mlnx_snap/snap_rpc_init.conf
elif (lspci -n -d 15b3: | grep -wq 'a2dc'); then
	# BlueField-3
	chroot /mnt rpm -e mlnx-snap || true
fi

	mkdir -p /mnt/etc/dhcp
	cat >> /mnt/etc/dhcp/dhclient.conf << EOF
send vendor-class-identifier "$DHCP_CLASS_ID_DP";
interface "oob_net0" {
  send vendor-class-identifier "$DHCP_CLASS_ID_OOB";
}
EOF

mkdir -p /mnt/etc/netplan
cat > /mnt/etc/netplan/60-mlnx.yaml << EOF
network:
    ethernets:
        oob_net0:
            renderer: networkd
            dhcp4: true
        tmfifo_net0:
            renderer: networkd
            addresses:
            - 192.168.100.2/30
            dhcp4: false
        enp3s0f0s0:
            renderer: networkd
            dhcp4: true
        enp3s0f1s0:
            renderer: networkd
            dhcp4: true
    version: 2
EOF

# Customisations per PSID
FLINT=""
if [ -x /usr/bin/mstflint ]; then
	FLINT=/usr/bin/mstflint
elif [ -x /usr/bin/flint ]; then
	FLINT=/usr/bin/flint
elif [ -x /mnt/usr/bin/mstflint ]; then
	FLINT=/mnt/usr/bin/mstflint
fi

pciid=`echo $pciids | awk '{print $1}' | head -1`
if [ -e /mnt/usr/sbin/mlnx_snap_check_emulation.sh ]; then
	sed -r -i -e "s@(NVME_SF_ECPF_DEV=).*@\1${pciid}@" /mnt/usr/sbin/mlnx_snap_check_emulation.sh
fi
if [ -n "$FLINT" ]; then
	PSID=`$FLINT -d $pciid q | grep PSID | awk '{print $NF}'`

	case "${PSID}" in
		MT_0000000634)
		sed -r -i -e 's@(EXTRA_ARGS=).*@\1"--mem-size 1200"@' /mnt/etc/default/mlnx_snap
		;;
	esac
fi

if [ "$WITH_NIC_FW_UPDATE" == "yes" ]; then
	if [ $NIC_FW_UPDATE_DONE -eq 0 ]; then
		fw_update
		NIC_FW_UPDATE_DONE=1
	fi
fi

# Clean up logs
/bin/rm -f /mnt/var/log/yum.log
/bin/rm -rf /mnt/tmp/*

if function_exists bfb_modify_os; then
	log "INFO: Running bfb_modify_os from bf.cfg"
	bfb_modify_os
fi

sync

unmount_partitions

sleep 1
blockdev --rereadpt ${device} > /dev/null 2>&1

fsck.vfat -a ${device}p1
fsck.ext4 -p -y ${device}p2
sync

bfrec --bootctl --policy dual 2> /dev/null || true
if [ -e /lib/firmware/mellanox/boot/capsule/boot_update2.cap ]; then
	bfrec --capsule /lib/firmware/mellanox/boot/capsule/boot_update2.cap --policy dual
fi

if [ -e /lib/firmware/mellanox/boot/capsule/efi_sbkeysync.cap ]; then
	bfrec --capsule /lib/firmware/mellanox/boot/capsule/efi_sbkeysync.cap
fi

# Clean up actual boot entries.
bfbootmgr --cleanall > /dev/null 2>&1

BFCFG=`which bfcfg 2> /dev/null`

mount -t efivarfs none /sys/firmware/efi/efivars
/bin/rm -f /sys/firmware/efi/efivars/Boot* > /dev/null 2>&1
/bin/rm -f /sys/firmware/efi/efivars/dump-* > /dev/null 2>&1
efibootmgr -c -d "$device" -p 1 -l "\boot\grub2\grubaa64.efi" -L $distro
umount /sys/firmware/efi/efivars

BFCFG=`which bfcfg 2> /dev/null`
if [ -n "$BFCFG" ]; then
	# Create PXE boot entries
	if [ -e /etc/bf.cfg ]; then
		mv /etc/bf.cfg /etc/bf.cfg.orig
	fi

	cat > /etc/bf.cfg << EOF
BOOT0=DISK
BOOT1=NET-NIC_P0-IPV4
BOOT2=NET-NIC_P0-IPV6
BOOT3=NET-NIC_P1-IPV4
BOOT4=NET-NIC_P1-IPV6
BOOT5=NET-OOB-IPV4
BOOT6=NET-OOB-IPV6
PXE_DHCP_CLASS_ID=$DHCP_CLASS_ID
EOF

	$BFCFG

	# Restore the original bf.cfg
	/bin/rm -f /etc/bf.cfg
	if [ -e /etc/bf.cfg.orig ]; then
		grep -v PXE_DHCP_CLASS_ID= /etc/bf.cfg.orig > /etc/bf.cfg
	fi
fi

if [ -n "$BFCFG" ]; then
	$BFCFG
fi

echo
echo "User/password is \"mariner/mariner\""
echo

if function_exists bfb_post_install; then
	log "INFO: Running bfb_post_install from bf.cfg"
	bfb_post_install
fi

log "INFO: Installation finished"

if [ "$WITH_NIC_FW_UPDATE" == "yes" ]; then
	if [ $NIC_FW_UPDATE_DONE -eq 1 ]; then
		# Reset NIC FW
		mount -t ext4 ${device}p2 /mnt
		bind_partitions
		fw_reset
		unmount_partitions
	fi
fi

sleep 3
log "INFO: Rebooting..."
# Wait for these messages to be pulled by the rshim service
sleep 3
