#!/bin/sh -x

if [ "$#" = "0" ]; then
	VMNAME="test"
else
	VMNAME="$1"
fi

echo "[Loading kernel module 'vmm']"
kldload vmm

echo "[Creating VM '$VMNAME' from kernel image: kernel.bin]"
bhyveload -k kernel.bin $VMNAME

if [ "$?" = "0" ]; then
	echo "[Starting VM '$VMNAME' with bvmconsole]"
	bhyve -e 0x80000000UL -m 128MB -b $VMNAME
else
	echo "[VM aborted]"
fi
