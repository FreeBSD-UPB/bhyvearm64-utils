#!/bin/bash

MODEL=/home/alex/data/bhyvearm64/Foundation_Platformpkg/models/Linux64_GCC-4.9/Foundation_Platform

BL1=/home/alex/data/bhyvearm64/uefi/bl1.bin
FIP=/home/alex/data/bhyvearm64/uefi/fip.bin
DISK_DIR=/home/alex/data/bhyvearm64/disk
DISK_NAME="disk.img"
DISK="${DISK_DIR}/${DISK_NAME}"

echo ""
echo "Running disk: ${DISK}"
echo ""

$MODEL  --cores=1 \
        --use-real-time \
        --arm-v8.0 \
        --gicv3 \
        --data=${BL1}@0x0 \
        --data=${FIP}@0x8000000 \
        --block-device=${DISK} \
