#!/bin/sh -x

if [ "$#" = "0" ]; then
	VMNAME="test"
else
	VMNAME="$1"
fi

echo "[Loading kernel module 'vmm']"
echo ""
kldload vmm

echo "[Starting VM '$VMNAME']"
echo ""
bhyve	\
	-c \
	-m 768MB \
	-l '/root/u-boot.bin' \
	-s '0x200@0x7000#44:virtio-blk,disk-aarch64-freebsd.img' \
	-s '0x1000@0x10000#37:mmio-uart' \
	$VMNAME
