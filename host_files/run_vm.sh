#!/bin/sh -x

[ "$#" = "0" ] && set VMNAME="test" || set VMNAME="$1"

echo "[Loading kernel module 'vmm']"
kldload vmm

echo "[Creating VM '$VMNAME' from kernel image: kernel.bin]"
bhyveload -k kernel.bin $VMNAME

if [ "$?" = "0" ]; then
	echo "[Starting VM '$VMNAME' with: bvmconsole]"
	bhyve -e 0x80000000UL -m 128MB -b $VMNAME
else
	echo "[VM aborted]"
fi
