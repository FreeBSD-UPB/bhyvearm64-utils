

# Description

This is a work in progress. The guest prints to stdout during the first boot steps, but it fails when it tries to initialize the GIC.

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
BUILD_STAGE=10 BUILD_GUEST=y ./build_arm64.sh
```

Do a full clean and rebuild everything:

```
DO_CLEAN=y BUILD_GUEST=y ./build_arm64.sh
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

#### Modify the script run_image.sh

You will need to modify the script run_image.sh to point to the correct locations for the Foundation Platform emulator (`$MODEL`), the uefi components (`$BL1` and `$FIP`) and the disk image you copied from the FreeBSD installation (`$DISK`).

#### Run the host

To run the host do:

```
./run_image.sh
```
The emulator will open an xterm window to interact with the host. The login name is root and it doesn't require a password.

#### Run the guest

When building the host disk image the guest kernel has been copied to `/root/kernel.bin` and a script to run the guest has been copied to `/root/start_vm.sh`. Running the script will create and run a virtual machine named `test`:

```
./run_image.sh
```

If you prefer to do it by hand:

Load the hypervisor kernel module:

```
kldload vmm
```

Load the guest kernel into memory:

```
bhyveload -k kernel.bin test
```

And start the guest with the bvmconsole enabled to allow guest output to stdout:

```
bhyve -b test
```

The guest will stop when it tries to initialize the Generic Interrupt Controller.
