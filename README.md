

# Description

The FreeBSD guest is able to boot and start a rescue shell. A minimal set of userspace programs is available. VirtIO devices are also available: virtio-net, virtio-blk, virtio-console and virtio-rnd (random device).

The FreeBSD host has been tested using the Foundation Platform emulator from ARM's website.


# Prerequisites

#### FreeBSD

You will have to have FreeBSD installed, either on bare metal or in a virtual machine. You will need it to compile the host and guest. I am using [FreeBSD11.0](https://www.freebsd.org/releases/11.0R/announce.html) in a KVM virtual machine with linux on bare metal.

#### Linux

You will need to have linux installed, either on bare metal or in a virtual machine. You will need it to run the Foundation Platform emulator which only works on linux. I have tested the emulator on Xubuntu 16.04 and Arch Linux.

#### Foundation Platform emulator

You will need the emulator to run the host and guest. You can download it from [ARM](https://silver.arm.com/browse/FM00A). Downloading it will require registration. You will also need to have xterm installed on linux.


# Compiling and running

The next steps are to be run from your **FreeBSD** installation.

#### Clone the FreeBSD fork

```
git clone -b projects/bhyvearm64 https://github.com/FreeBSD-UPB/freebsd.git
```

Make sure you are on branch **projects/bhyvearm64** for the next steps.

#### Clone the utility scripts

```
git clone https://github.com/FreeBSD-UPB/bhyvearm64-utils.git
```

#### Modify the script build_arm64.sh

Modify the script build_arm64.sh by having the variable `$WORKSPACE` point to the parent directory where you cloned the FreeBSD repo. The default value assumes that you have the FreeBSD repo in `$HOME/arm64-workspace/freebsd`. After building the disk image the script will try to rsync the image to the linux installation for the Platform emulator to use. You can set the exact location by modifying the variable `$RSYNC_TARGET` in the file.

#### Build the FreeBSD disk image

```
BUILD_GUEST=y ./build_arm64.sh
```

This will do a buildworld and compile the host and the guest kernel and ramdisk. You can skip a certain compile stage if you want to. For example, let's say that you've already built the world and you only want to rebuild the host kernel:

```
BUILD_STAGE=999 ./build_arm64.sh
```

If you only want to rebuild the guest:

```
BUILD_STAGE=10 NO_KERNEL=y BUILD_GUEST=y ./build_arm64.sh
```

Do a full clean and rebuild everything:

```
FULL_CLEAN=y BUILD_GUEST=y ./build_arm64.sh
```
If you haven't specified a rsync target in the build_arm64.sh script make sure you copy the disk image to you linux installation.

#### Copy the script run_image.sh

You will need to copy the script run_image.sh from the utility scripts to you linux installation.

The next steps are to be run from **linux**.

#### Download and extract the UEFI for the Foundation emulator

```
wget http://snapshots.linaro.org/member-builds/armlt-platforms-release/$RELEASE/fvp-uefi.zip
unzip fvp-uefi.zip
```
and replace `$RELEASE` with the latest uefi release. FreeBSD was tested with version 51.

UPDATE: I have tested the new release, version 61, and it isn't working with the 11.3 version of the Foundation Emulator. I have uploaded in this repository UEFI version 51 that is working.

#### Modify the script run_image.sh

You will need to modify the script run_image.sh to point to the correct locations for the Foundation Platform emulator (`$MODEL`), the uefi components (`$BL1` and `$FIP`) and the disk image you copied from the FreeBSD installation (`$DISK`).

#### Run the host

To run the host do:

```
./run_image.sh
```
The emulator will open an xterm window to interact with the host. The login name is root and it doesn't require a password.

#### Run the guest

When building the host disk image the guest kernel has been copied to `/root/kernel.bin` and two scripts have been provides to run the guest: `/root/run_vm.sh` and `/root/virtio_run.sh`. `run_vm.sh` will run a guest that has been compiled without virtio devices. `virtio_run.sh` can be used to run a guest with virtio devices. Running the script without any arguments will create and run a virtual machine with the default name `test`. One argument can be provided to specify the name of the virtual machine.

```
./run_image.sh vm
```

#### VirtIO

Four VirtIO devices are available: virtio-blk, virtio-net, virtio-console and virtio-rnd. The guest has to be configured with the devices in the DTS (`freebsd/dts/arm64/foundation-v8-gicv3-guest.dts`) file and the drivers need to be compiled in the kernel (`freebsd/arm64/conf/FOUNDATION_GUEST`).

The virtio arguments given the bhyve must match the devices defined in the DTS file. The script `virtio_run.sh` can be used an example.

##### virtio-net

The script `virtio_run.sh` will automatically create a tap and a bridge device for the host to connect to. The bridge device has the 10.0.4.1/24. In order to communicate with the host, the guest must configure the virtual NIC with an address in the same network (like 10.0.4.2/24).


##### virtio-blk

The host is compiled with a virtio image that can be used by the guest.

To mount the image from the host:

`# mdconfig -f virtio.img`
`# mount /dev/mdX /mnt`

To mount the image from the guest:

`# mount -o rw /` # The guest ramdisk is mounted read-only. Remount it as read-write to create the mountpoint.
`# mkdir mountpoint`
`# mount /dev/vtbd0 mountpoint`

##### virtio-console

By using the virtio-console, the guest is able to communicate with the host via a socket file. The script `virtio_run.sh`configures the virtio-console to use the socket file `socket_<VMname>.skt`. The socket file must **NOT** exist on the host. The script deletes the socket file, if it exists, before starting the virtual machine.

To connect to the socket, the host can use `# nc -U <socket_file>`.

On the guest:

`mount -o rw /`		# Remount the guest ramdisk as read-write to allow `cu` to create the lock file.
`cu -l /dev/ttyV0.0`	# Connect to the virtual console.
