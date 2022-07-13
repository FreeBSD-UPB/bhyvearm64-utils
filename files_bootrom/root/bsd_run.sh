#!/bin/sh -x

if [ "$#" = "0" ]; then
	VMNAME="test"
else
	VMNAME="$1"
fi

echo ""
echo "[Starting sshd]"
echo ""
/usr/sbin/sshd

echo "[Loading kernel module 'vmm']"
echo ""
kldload vmm

#echo "[Starting VM '$VMNAME' with: bvmconsole, virtio-blk, virtio-net, virtio-console, virtio-rnd]"
echo "[Starting VM '$VMNAME' with: bvmconsole, virtio-blk, virtio-net, virtio-rnd]"
echo ""

bhyve	\
	-c \
	-p 0:0 \
	-p 1:1 \
	-m 768MB \
	-l '/root/u-boot.bin' \
	-s '0x200@0x7000#44:virtio-blk,disk-aarch64-freebsd.img' \
	-s '0x1000@0x10000#37:mmio-uart' \
	$VMNAME
