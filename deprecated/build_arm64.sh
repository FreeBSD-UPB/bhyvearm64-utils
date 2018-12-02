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

echo_msg() {
	echo ""		| tee -a ${LOGFILE}
	echo "$1"	| tee -a ${LOGFILE}
	echo ""		| tee -a ${LOGFILE}
}

exit_on_failure() {
	exitcode=$?
	echo_msg "Error: $1 failed in ${SRC}"
	if [ -n "${RESTORE_GUEST}" ] && [ -f $WORKSPACE/.kernel_guest ]; then
		mv -f $WORKSPACE/.kernel_guest $OBJDIR/sys/FOUNDATION_GUEST/kernel_guest
	fi
	exit $exitcode
}

export TARGET=arm64

#
# Predefined path to workspace
#
export WORKSPACE=$(realpath $HOME)/arm64-workspace/
export MAKEOBJDIRPREFIX=$WORKSPACE/obj/
export ROOTFS=$WORKSPACE/rootfs/
export OBJDIR=$MAKEOBJDIRPREFIX/$WORKSPACE/freebsd/arm64.aarch64


#
# Build from scratch if a specific build stage is not specified
#
BUILD_STAGE="${BUILD_STAGE:-0}"

#
# Truncate the log file to zero.
#
LOGFILE=$(realpath $HOME)/log
>${LOGFILE}

echo_msg "Build stage: ${BUILD_STAGE}"
echo_msg "Log file: ${LOGFILE}"

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
	echo_msg "Sources set to: ${SRC}"
else
	export SRC=$(realpath $1)
fi

if [ ! -d "${SRC}" ]; then
	echo_msg "Error: Provided path (${SRC}) is not a directory"
	exit 1
fi

export MAKESYSPATH=$SRC/share/mk
if [ ! -d "$MAKESYSPATH" ]; then
	echo_msg "Error: Can't find svn src tree"
	exit 1
fi

#
# Always include the guest ramdisk in the final image.
#
if [ ${BUILD_STAGE} -eq 0 ] && [ -z ${BUILD_GUEST} ]; then
	if [ -f $OBJDIR/sys/FOUNDATION_GUEST/kernel_guest ]; then
		cp -f $OBJDIR/sys/FOUNDATION_GUEST/kernel_guest $WORKSPACE/.kernel_guest
		RESTORE_GUEST=y
	else
		BUILD_GUEST=y
	fi
fi

#
# Create dirs
#
mkdir -p $ROOTFS $MAKEOBJDIRPREFIX

#
# Clean first
#
if [ -n "${FULL_CLEAN}" ] && [ ${BUILD_STAGE} -eq 0 ]; then
	echo_msg "Doing cleandir"
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
# Number of CPU for parallel build
#
export NCPU=$(sysctl -n hw.ncpu)

#
# Build FreeBSD
#
cd $SRC
if [ ${BUILD_STAGE} -eq 0 ]; then

	echo_msg "Building world"

	make -j $NCPU -DNO_CLEAN -DMODULES_OVERRIDE=vmm buildworld | tee -a ${LOGFILE}
	if [ ${PIPESTATUS} -ne 0 ]; then
		exit_on_failure "buildworld"
	fi
fi

#
# Build the guest ramdisk
#
if [ -n "${BUILD_GUEST}" ]; then

	echo_msg "Building guest ramdisk"

	# Create the guest ramdisk
	RAMDISKDIR=$WORKSPACE/ramdisk
	cd $RAMDISKDIR
	rm -rf ramdisk-guest.img &> /dev/null
	makefs -t ffs -B little -o optimization=space -o version=1 \
		ramdisk-guest.img ramdisk-v2.mtree | tee -a ${LOGFILE}
	if [ ${PIPESTATUS} -ne 0 ]; then
		exit_on_failure "build guest ramdisk"
	fi

	# Create the guest kernel
	cd $SRC
	#mv -f sys/arm64/arm64/locore.S sys/arm64/arm64/locore.S.bck
	#cp -f sys/arm64/arm64/locore_guest.S sys/arm64/arm64/locore.S

	make -j $NCPU KERNCONF=FOUNDATION_GUEST \
		-DWITHOUT_BHYVE \
		-DNO_CLEAN \
		-DMODULES_OVERRIDE='' \
		buildkernel | tee -a ${LOGFILE}
	if [ ${PIPESTATUS} -ne 0 ]; then
		# Restore the host locore.S
		#mv -f sys/arm64/arm64/locore.S.bck sys/arm64/arm64/locore.S
		exit_on_failure "buildkernel guest"
	fi

	cp -f $OBJDIR/sys/FOUNDATION_GUEST/kernel $OBJDIR/sys/FOUNDATION_GUEST/kernel_guest
	#rm -f $OBJDIR/sys/FOUNDATION_GUEST/kernel.debug
	#rm -f $OBJDIR/sys/FOUNDATION_GUEST/kernel.full

	#mv -f sys/arm64/arm64/locore.S.bck sys/arm64/arm64/locore.S
fi

#
# Build the host kernel
#
if [ -z "${NO_KERNEL}" ]; then
	if [ ${BUILD_STAGE} -le 1 ] || [ ${BUILD_STAGE} -eq 999 ]; then
		echo_msg "Building host kernel"
		make -j $NCPU KERNCONF=FOUNDATION \
			-DNO_CLEAN \
			-DMODULES_OVERRIDE=vmm \
			buildkernel | tee -a ${LOGFILE}
		if [ ${PIPESTATUS} -ne 0 ]; then
			exit_on_failure "buildkernel"
		fi
	fi
fi

#
# Install FreeBSD
#
if [ -n "$DO_INSTALL1" ]; then
	if [ ${BUILD_STAGE} -le 2 ]; then
		make -DNO_ROOT DESTDIR=$ROOTFS installworld | \
			tee -a ${LOGFILE}
		if [ ${PIPESTATUS} -ne 0 ]; then
			exit_on_failure "installworld"
		fi
	fi
	if [ ${BUILD_STAGE} -le 3 ]; then
		make -DNO_ROOT DESTDIR=$ROOTFS distribution | \
			tee -a ${LOGFILE}
		if [ ${PIPESTATUS} -ne 0 ]; then
			exit_on_failure "distribution"
		fi
	fi

	make -DNO_ROOT DESTDIR=$ROOTFS installkernel KERNCONF=FOUNDATION | \
		tee -a ${LOGFILE}
	if [ ${PIPESTATUS} -ne 0 ]; then
		exit_on_failure "installkernel"
	fi

	#cp -f $WORKSPACE/files_host/custom_metalog $ROOTFS/METALOG

	# Remove all traces of make install{world, kernel} and make distribution
	# ignoring -DNO_ROOT
	sed -ie 's/\/usr\/home\/alex\/arm64-workspace\/\/rootfs//' $ROOTFS/METALOG

	#
	# Setup rootfs.
	#
	echo '/dev/vtbd0s2 / ufs rw,noatime 1 1' > $ROOTFS/etc/fstab | \
		tee -a ${LOGFILE}
	echo './etc/fstab type=file uname=root gname=wheel mode=644' >> $ROOTFS/METALOG | \
		tee -a ${LOGFILE}

	#
	# Copy the VM run script.
	#
	cp -f ${WORKSPACE}/files_host/run_vm.sh $ROOTFS/root/run_vm.sh | \
		tee -a ${LOGFILE}
	if [ ${PIPESTATUS} -ne 0 ]; then
		exit_on_failure "${WORKSPACE}/files_host/run_vm.sh"
	fi
	grep '/root/run_vm.sh' $ROOTFS/METALOG &> /dev/null
	if [ "$?" != "0" ]; then
		s=$(($(cat $ROOTFS/root/run_vm.sh | wc -c)))
		echo "./root/run_vm.sh type=file uname=root gname=wheel mode=755 size=$s" >> $ROOTFS/METALOG
	fi

	#
	# Copy the VM with virtio run script.
	#
	cp -f ${WORKSPACE}/files_host/virtio_run.sh $ROOTFS/root/virtio_run.sh | \
		tee -a ${LOGFILE}
	if [ ${PIPESTATUS} -ne 0 ]; then
		exit_on_failure "${WORKSPACE}/files_host/virtio_run.sh"
	fi
	grep '/root/virtio_run.sh' $ROOTFS/METALOG &> /dev/null
	if [ "$?" != "0" ]; then
		s=$(($(cat $ROOTFS/root/virtio_run.sh | wc -c)))
		echo "./root/virtio_run.sh type=file uname=root gname=wheel mode=755 size=$s" >> $ROOTFS/METALOG
	fi

	#
	# Copy test file for virtio
	#
	cp -f ${WORKSPACE}/files_host/virtio.img $ROOTFS/root/virtio.img | \
		tee -a ${LOGFILE}
	if [ ${PIPESTATUS} -ne 0 ]; then
		exit_on_failure "${WORKSPACE}/files_host/virtio_run.sh"
	fi
	grep '/root/virtio.img' $ROOTFS/METALOG &> /dev/null
	if [ "$?" != "0" ]; then
		s=$(($(cat $ROOTFS/root/virtio.img | wc -c)))
		echo "./root/virtio.img type=file uname=root gname=wheel mode=777 size=$s" >> $ROOTFS/METALOG
	fi

	#
	# Copy ssh files
	#
	cp -f ${WORKSPACE}/files_host/ssh_host_rsa_key $ROOTFS/etc/ssh/ssh_host_rsa_key | \
		tee -a ${LOGFILE}
	if [ ${PIPESTATUS} -ne 0 ]; then
		exit_on_failure "${WORKSPACE}/files_host/ssh_host_rsa_key"
	fi
	grep '/etc/ssh/ssh_host_rsa_key' $ROOTFS/METALOG &> /dev/null
	if [ "$?" != "0" ]; then
		s=$(($(cat $ROOTFS/etc/ssh/ssh_host_rsa_key | wc -c)))
		echo "./etc/ssh/ssh_host_rsa_key type=file uname=root gname=wheel mode=600 size=$s" >> $ROOTFS/METALOG
	fi

	cp -f ${WORKSPACE}/files_host/ssh_host_rsa_key.pub $ROOTFS/etc/ssh/ssh_host_rsa_key.pub | \
		tee -a ${LOGFILE}
	if [ ${PIPESTATUS} -ne 0 ]; then
		exit_on_failure "${WORKSPACE}/files_host/ssh_host_rsa_key.pub"
	fi
	grep '/etc/ssh/ssh_host_rsa_key.pub' $ROOTFS/METALOG &> /dev/null
	if [ "$?" != "0" ]; then
		s=$(($(cat $ROOTFS/etc/ssh/ssh_host_rsa_key.pub | wc -c)))
		echo "./etc/ssh/ssh_host_rsa_key.pub type=file uname=root gname=wheel mode=600 size=$s" >> $ROOTFS/METALOG
	fi

	cp -f ${WORKSPACE}/files_host/sshd_config $ROOTFS/etc/ssh/sshd_config | \
		tee -a ${LOGFILE}
	if [ ${PIPESTATUS} -ne 0 ]; then
		exit_on_failure "${WORKSPACE}/files_host/sshd_config"
	fi
	grep '/etc/ssh/ssh_host_rsa_key.pub' $ROOTFS/METALOG &> /dev/null
	if [ "$?" != "0" ]; then
		s=$(($(cat $ROOTFS/etc/ssh/sshd_config | wc -c)))
		echo "./etc/ssh/sshd_config type=file uname=root gname=wheel mode=644 size=$s" >> $ROOTFS/METALOG
	fi

	#
	# Copy rescue for netcat.
	#
	cp -f ${ROOTFS}/rescue/nc $ROOTFS/usr/bin/nc | tee -a ${LOGFILE}
	if [ ${PIPESTATUS} -ne 0 ]; then
		exit_on_failure "${WORKSPACE}/rescue/nc"
	fi
	grep '/usr/bin/nc' $ROOTFS/METALOG &> /dev/null
	if [ "$?" != "0" ]; then
		s=$(($(cat $ROOTFS/usr/bin/nc | wc -c)))
		echo "./usr/bin/nc type=file uname=root gname=wheel mode=555 size=$s" >> $ROOTFS/METALOG
	fi

	#
	# Copy the guest image.
	#
	echo_msg "Copying guest image"
	if [ -n "${RESTORE_GUEST}" ]; then
		mv -f $WORKSPACE/.kernel_guest $OBJDIR/sys/FOUNDATION_GUEST/kernel_guest
	fi
	cp -f $OBJDIR/sys/FOUNDATION_GUEST/kernel_guest $ROOTFS/root/kernel.bin
	grep '/root/kernel.bin' $ROOTFS/METALOG &> /dev/null
	if [ "$?" != "0" ]; then
		s=$(($(cat $ROOTFS/root/kernel.bin | wc -c)))
		echo "./root/kernel.bin type=file uname=root gname=wheel mode=644 size=$s" >> $ROOTFS/METALOG
	fi

	#
	# time= workaround
	#
	sed -i '' -E 's/(time=[0-9]*)\.[0-9]*/\1.0/' $ROOTFS/METALOG | \
		tee -a ${LOGFILE}

	IMGDIR=$ROOTFS
	MTREE=$ROOTFS/METALOG
else
	IMGDIR=$WORKSPACE
	MTREE=$WORKSPACE/files_host/host_small.mtree
fi

if [ -z "$NO_SYNC" ]; then

	rm -rf ${IMGDIR}/rootfs.img
	rm -rf ${WORKSPACE}/disk.img

	#
	# Rootfs image.
	#
	cd $IMGDIR && \
		/usr/sbin/makefs -m 2560393216 -D ${IMGDIR}/rootfs.img $MTREE 2> $(realpath $HOME)/makefs_errors | tee -a ${LOGFILE}
	if [ ${PIPESTATUS} -ne 0 ]; then
		exit_on_failure "/usr/sbin/makefs"
	fi

	#
	# Final ARM64 image. Notice: you may have to update your mkimg(1) from svn src head.
	#
	EFI_IMG=$OBJDIR/stand/efi/boot1/boot1.efifat
	echo "Using $EFI_IMG" | tee -a ${LOGFILE}
	/usr/bin/mkimg	-s gpt \
			-p efi:=$EFI_IMG \
			-p freebsd:=${IMGDIR}/rootfs.img \
			-o ${WORKSPACE}/disk.img | tee -a ${LOGFILE}
	if [ ${PIPESTATUS} -ne 0 ]; then
		exit_on_failure "/usr/bin/mkimg"
	fi

	echo "Disk image ready: $WORKSPACE/disk.img" | tee -a ${LOGFILE}

	#
	# Copy the disk to the host.
	#
	if [ -z "${RSYNC_TARGET}" ]; then
		RSYNC_TARGET=host:/home/alex/data/bhyvearm64/disk
	fi
	TARGET_DISK="disk.img"

	rsync -arPhh ${WORKSPACE}/disk.img "${RSYNC_TARGET}"/${TARGET_DISK} --checksum | \
		tee -a ${LOGFILE}
	exitcode="${PIPESTATUS}"
	if [ "$exitcode" = "0" ]; then
		echo_msg "Disk image synced to host: ${RSYNC_TARGET}/${TARGET_DISK}"
	else
		echo_msg "Error: cannot sync disk image to ${RSYNC_TARGET}/${TARGET_DISK}"
		exit $exitcode
	fi
fi

echo_msg "$(date)"
