#!/bin/sh

echo ""
echo "[Loading vmm kernel module...]"
echo ""
kldload vmm

echo ""
echo "[Calling bhyveload to load the kernel...]"
echo ""
bhyveload -k kernel.bin test

if [ "$?" = "0" ]; then
	echo ""
	echo "[Starting VM with BVM Console...]"
	echo ""
	bhyve -b test
else
	echo ""
	echo "[VM aborted]"
	echo ""
fi
