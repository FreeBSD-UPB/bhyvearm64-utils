#!/usr/bin/env bash
#-
# Copyright (c) 2015 Ruslan Bukin <br@bsdpad.com>
# All rights reserved.
#
# This software was developed by the University of Cambridge Computer
# Laboratory as part of the CTSRD Project, with support from the UK Higher
# Education Innovation Fund (HEIF).
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#

export TARGET=arm64

#
# Predefined path to workspace
#
export WORKSPACE=$(realpath $HOME)/arm64-workspace/
export MAKEOBJDIRPREFIX=$WORKSPACE/obj/
export ROOTFS=$WORKSPACE/rootfs/

#
# Build from scratch if a specific build stage is not specified
#
BUILD_STAGE="${BUILD_STAGE:-0}"

#
# Truncate the log file to zero.
#
LOGFILE=$(realpath $HOME)/log
>${LOGFILE}

echo "" 				| tee -a ${LOGFILE}
echo "Build stage: ${BUILD_STAGE}" 	| tee -a ${LOGFILE}
echo ""					| tee -a ${LOGFILE}
echo "Log file: ${LOGFILE}"		| tee -a ${LOGFILE}
echo ""					| tee -a ${LOGFILE}

exit_on_failure() {
	exitcode=$?
	echo "Error: $1 failed in ${SRC}"	| tee -a ${LOGFILE}
	if [ -n "${RESTORE_GUEST}" ] && [ -f $WORKSPACE/.kernel_guest ]; then
		mv -f $WORKSPACE/.kernel_guest $ODIR/sys/FOUNDATION_GUEST/kernel_guest
	fi
	exit $exitcode
}

#
# Sanity checks
#
if [ "$USER" == "root" ]; then
	echo "Error: Can't run under root"	| tee -a ${LOGFILE}
	exit 1
fi

if [ "$(uname -s)" != "FreeBSD" ]; then
	echo "Error: Can run on FreeBSD only"	| tee -a ${LOGFILE}
	exit 1
fi

#
# Get path to SRC tree
#
if [ -z "$1" ]; then
	SRC=${WORKSPACE}/freebsd/
	echo "Sources set to: ${SRC}"		| tee -a ${LOGFILE}
else
	export SRC=$(realpath $1)
fi

if [ ! -d "${SRC}" ]; then
	echo "Error: Provided path (${SRC}) is not a directory"	| tee -a ${LOGFILE}
	exit 1
fi

export MAKESYSPATH=$SRC/share/mk
if [ ! -d "$MAKESYSPATH" ]; then
	echo "Error: Can't find svn src tree" 	| tee -a ${LOGFILE}
	exit 1
fi

export ODIR=$MAKEOBJDIRPREFIX/arm64.aarch64/$SRC

#
# Create dirs
#
mkdir -p $ROOTFS $MAKEOBJDIRPREFIX

#
# Clean first
#
if [ -n "${FULL_CLEAN}" ] && [ ${BUILD_STAGE} -eq 0 ]; then
	echo "Doing cleandir"	| tee -a ${LOGFILE}
	cd $SRC && \
		make cleandir && \
		make cleandir
	rm -rf $MAKEOBJDIRPREFIX
	mkdir $MAKEOBJDIRPREFIX
	DNO_CLEAN=""
else
	DNO_CLEAN="-DNO_CLEAN"
fi

#
# Always include the guest ramdisk in the final image.
#
if [ ${BUILD_STAGE} -eq 0 ] && [ -z ${BUILD_GUEST} ]; then
	if [ -f $ODIR/sys/FOUNDATION_GUEST/kernel_guest ]; then
		mv -f $ODIR/sys/FOUNDATION_GUEST/kernel_guest $WORKSPACE/.kernel_guest
		RESTORE_GUEST=y
	else
		BUILD_GUEST=y
	fi
fi

#
# Number of CPU for parallel build
#
export NCPU=$(sysctl -n hw.ncpu)

#
# Build FreeBSD
#
cd $SRC
if [ ${BUILD_STAGE} -eq 0 ]; then
	make -j $NCPU -DWITHOUT_TESTS -DELF_VERBOSE ${DNO_CLEAN} buildworld | tee -a ${LOGFILE}
	if [ ${PIPESTATUS} -ne 0 ]; then
		exit_on_failure "buildworld"
	fi
fi

#
# Build the guest ramdisk
#
if [ -n "${BUILD_GUEST}" ]; then

	echo ""
	echo "Building guest ramdisk"
	echo ""

	# Create the guest ramdisk
	RAMDISKDIR=$WORKSPACE/ramdisk
	cd $RAMDISKDIR
	makefs -t ffs -B little -o optimization=space -o version=1 \
		ramdisk-guest.img ramdisk-guest.mtree

	# Create the guest kernel
	cd $SRC
	mv -f sys/arm64/arm64/locore.S sys/arm64/arm64/locore.S.bck
	mv -f sys/arm64/arm64/machdep.c sys/arm64/arm64/machdep.c.bck
	mv -f sys/arm64/arm64/pmap.c sys/arm64/arm64/pmap.c.bck
	mv -f sys/dev/fdt/fdt_common.c sys/dev/fdt/fdt_common.c.bck
	cp -f sys/arm64/arm64/locore_guest.S sys/arm64/arm64/locore.S
	cp -f sys/arm64/arm64/machdep_guest.c sys/arm64/arm64/machdep.c
	cp -f sys/arm64/arm64/pmap_guest.c sys/arm64/arm64/pmap.c
	cp -f sys/dev/fdt/fdt_common_guest.c sys/dev/fdt/fdt_common.c
	make -j $NCPU buildkernel -DWITHOUT_BHYVE KERNCONF=FOUNDATION_GUEST | \
		tee -a ${LOGFILE}
	if [ ${PIPESTATUS} -ne 0 ]; then
		# Restore the host locore.S
		mv -f sys/arm64/arm64/locore.S.bck sys/arm64/arm64/locore.S
		mv -f sys/arm64/arm64/machdep.c.bck sys/arm64/arm64/machdep.c
		mv -f sys/arm64/arm64/pmap.c.bck sys/arm64/arm64/pmap.c
		mv -f sys/dev/fdt/fdt_common.c.bck sys/dev/fdt/fdt_common.c
		exit_on_failure "buildkernel guest"
	fi
	mv -f $ODIR/sys/FOUNDATION_GUEST/kernel $ODIR/sys/FOUNDATION_GUEST/kernel_guest
	rm -f $ODIR/sys/FOUNDATION_GUEST/kernel.debug
	rm -f $ODIR/sys/FOUNDATION_GUEST/kernel.full
	mv -f sys/arm64/arm64/locore.S.bck sys/arm64/arm64/locore.S
	mv -f sys/arm64/arm64/machdep.c.bck sys/arm64/arm64/machdep.c
	mv -f sys/arm64/arm64/pmap.c.bck sys/arm64/arm64/pmap.c
	mv -f sys/dev/fdt/fdt_common.c.bck sys/dev/fdt/fdt_common.c
fi

#
# Build the host kernel
#
if [ ${BUILD_STAGE} -le 1 ] || [ ${BUILD_STAGE} -eq 999 ]; then
	make -j $NCPU -DELF_VERBOSE buildkernel KERNCONF=FOUNDATION | tee -a ${LOGFILE}
	if [ ${PIPESTATUS} -ne 0 ]; then
		exit_on_failure "buildkernel"
	fi
fi

if [ -z "${NO_SYNC}" ]; then

	#
	# Install FreeBSD
	#
	if [ ${BUILD_STAGE} -le 2 ]; then
		make -DNO_ROOT -DWITHOUT_TESTS DESTDIR=$ROOTFS installworld | \
			tee -a ${LOGFILE}
		if [ ${PIPESTATUS} -ne 0 ]; then
			exit_on_failure "installworld"
		fi
	fi
	if [ ${BUILD_STAGE} -le 3 ]; then
		make -DNO_ROOT -DWITHOUT_TESTS DESTDIR=$ROOTFS distribution | \
			tee -a ${LOGFILE}
		if [ ${PIPESTATUS} -ne 0 ]; then
			exit_on_failure "distribution"
		fi
	fi

	make -DNO_ROOT -DWITHOUT_TESTS DESTDIR=$ROOTFS installkernel KERNCONF=FOUNDATION | \
		tee -a ${LOGFILE}
	if [ ${PIPESTATUS} -ne 0 ]; then
		exit_on_failure "installkernel"
	fi

	# Remove all traces of make install{world, kernel} and make distribution
	# ignoring -DNO_ROOT
	sed -ie 's/\/usr\/home\/alex\/arm64-workspace\/\/rootfs//' $ROOTFS/METALOG

	#
	# Setup rootfs for QEMU
	#
	echo '/dev/vtbd0s2 / ufs rw,noatime 1 1' > $ROOTFS/etc/fstab | \
		tee -a ${LOGFILE}
	echo './etc/fstab type=file uname=root gname=wheel mode=644' >> $ROOTFS/METALOG | \
		tee -a ${LOGFILE}

	#
	# Copy the VM run script.
	#
	cp -f ${WORKSPACE}/start_vm.sh $ROOTFS/root/
	echo './root/start_vm.sh type=file uname=root gname=wheel mode=644' >> $ROOTFS/METALOG

	#
	# Copy the guest ramdisk.
	#
	echo ""
	echo "Copying guest image"
	echo ""

	# Copy the guest image
	if [ -n "${RESTORE_GUEST}" ]; then
		mv -f $WORKSPACE/.kernel_guest $ODIR/sys/FOUNDATION_GUEST/kernel_guest
	fi
	cp -f $ODIR/sys/FOUNDATION_GUEST/kernel_guest $ROOTFS/root/kernel.bin
	echo './root/kernel.bin type=file uname=root gname=wheel mode=644' >> $ROOTFS/METALOG

	#
	# time= workaround
	#
	sed -i '' -E 's/(time=[0-9]*)\.[0-9]*/\1.0/' $ROOTFS/METALOG | \
		tee -a ${LOGFILE}

	#
	# Rootfs image. 1G size, 10k free inodes
	#
	cd $ROOTFS && \
		/usr/sbin/makefs -f 10000 -s 1560395776 -D rootfs.img METALOG 2> $(realpath $HOME)/makefs_errors | tee -a ${LOGFILE}
	if [ ${PIPESTATUS} -ne 0 ]; then
		exit_on_failure "/usr/sbin/makefs"
	fi

	#
	# Final ARM64 image. Notice: you may have to update your mkimg(1) from svn src head.
	#
	echo "Using $WORKSPACE/obj/arm64.aarch64/$SRC/sys/boot/efi/boot1/boot1.efifat" | \
		tee -a ${LOGFILE}
	/usr/bin/mkimg -s mbr -p efi:=$MAKEOBJDIRPREFIX/arm64.aarch64/$SRC/sys/boot/efi/boot1/boot1.efifat -p freebsd:=rootfs.img -o disk.img | \
		tee -a ${LOGFILE}
	if [ ${PIPESTATUS} -ne 0 ]; then
		exit_on_failure "/usr/bin/mkimg"
	fi

	echo "Disk image ready: $ROOTFS/disk.img" | tee -a ${LOGFILE}

	#
	# Copy the disk to the host.
	#
	if [ -z "${RSYNC_TARGET}" ]; then
		RSYNC_TARGET=host:/home/alex/data/bhyvearm64/disk
	fi
	TARGET_DISK="disk.img"

	rsync -arPhh ${ROOTFS}/disk.img "${RSYNC_TARGET}"/${TARGET_DISK} --checksum | \
		tee -a ${LOGFILE}
	exitcode="${PIPESTATUS}"
	if [ "$exitcode" -eq "0" ]; then
		echo "Disk image synced to host: ${RSYNC_TARGET}/${TARGET_DISK}" | \
			tee -a ${LOGFILE}
	else
		echo "Error: cannot sync disk image to ${RSYNC_TARGET}/${TARGET_DISK}" | \
			tee -a ${LOGFILE}
		exit $exitcode
	fi
fi

echo ""
date
echo ""
