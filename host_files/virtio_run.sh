#!/bin/sh

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
mount -o rw /

CONS_SOCK="/root/console_${VMNAME}.skt"

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

ifconfig

echo ""
echo "[Starting sshd]"
echo ""
/usr/sbin/sshd

echo "[Loading kernel module 'vmm']"
echo ""
kldload vmm

cd /root

echo ""
echo "[Creating VM '$VMNAME' from kernel image: payload.bin]"
echo ""
bhyveload -k payload.bin $VMNAME

#rm -f "${CONS_SOCK}"

#echo "[Starting VM '$VMNAME' with: bvmconsole, virtio-blk, virtio-net, virtio-console, virtio-rnd]"
echo "[Starting VM '$VMNAME' with: bvmconsole, virtio-blk, virtio-net, virtio-rnd]"
echo ""
bhyve	\
	-e 0x80000000UL \
	-m 128MB \
	-s '0x200@0x7000#24:virtio-blk,virtio.img' \
	-s "0x200@0x6000#23:virtio-net,${TAPDEV}" \
	-s "0x200@0x5000#22:virtio-console,sock=${CONS_SOCK}" \
	-s '0x200@0x4000#-1:virtio-rnd' \
	-b $VMNAME
