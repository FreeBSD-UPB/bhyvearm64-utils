#!/bin/sh

echo ""
echo "[Loading vmm kernel module...]"
echo ""
kldload vmm

echo ""
echo "[Calling bhyveload -e var1=val1 -e var2=val2 to load the kernel...]"
echo ""
bhyveload -k kernel.bin -e var1=val1 -e var2=val2 test

echo ""
echo "[Starting VM with BVM Console...]"
echo ""
bhyve -b test
