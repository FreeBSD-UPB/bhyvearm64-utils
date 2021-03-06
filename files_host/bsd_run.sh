#!/bin/sh -x

NIC="smc0"
BRIDGE="bridge0"
# Different VMs must use different tap devices.
TAPDEV="tap0"

if [ "$#" = "0" ]; then
	VMNAME="test"
else
	VMNAME="$1"
fi

# Make filesystem writable.
mount -uf /

CONS_SOCK="console_${VMNAME}.skt"

echo ""
echo "[Configuring network interfaces]"
echo ""

# Create an configure interfaces for VirtIO network.
ifconfig bridge create
ifconfig $BRIDGE addm $NIC
ifconfig $BRIDGE inet 10.0.4.1 netmask 255.255.255.0

ifconfig $TAPDEV create
ifconfig $BRIDGE addm $TAPDEV
ifconfig $TAPDEV up

ifconfig $NIC inet 192.0.0.1 netmask 255.255.255.0

ifconfig

echo ""
echo "[Starting sshd]"
echo ""
/usr/sbin/sshd

echo "[Loading kernel module 'vmm']"
echo ""
kldload vmm

echo ""
echo "[Creating VM '$VMNAME' from kernel image: payload.bin]"
echo ""
bhyveload -k kernel -t device-tree.dtb $VMNAME

rm -f "${CONS_SOCK}" &> /dev/null

#echo "[Starting VM '$VMNAME' with: bvmconsole, virtio-blk, virtio-net, virtio-console, virtio-rnd]"
echo "[Starting VM '$VMNAME' with: bvmconsole, virtio-blk, virtio-net, virtio-rnd]"
echo ""
bhyve	\
	-c \
	-m 128MB \
	-s '0x200@0x7000#44:virtio-blk,virtio.img' \
	-s "0x200@0x6000#43:virtio-net,${TAPDEV}" \
	-s "0x200@0x5000#42:virtio-console,sock=${CONS_SOCK}" \
	-s '0x200@0x4000#-1:virtio-rnd' \
	-s '0x1000@0x10000#37:mmio-uart' \
	$VMNAME
