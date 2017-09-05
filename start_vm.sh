#!/bin/sh

echo ""
echo "[Loading vmm kernel module...]"
echo ""
kldload vmm

echo ""
echo "[Calling bhyveload to load the kernel...]"
echo ""
bhyveload -k kernel.bin test

echo ""
echo "[Starting VM...]"
echo ""
bhyve test
