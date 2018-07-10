#/bin/sh -x

[ "$#" = "0" ] && set VMNAME="test" || set VMNAME="$1"

echo ""
echo "[Configuring network interfaces]"
echo ""

# Create an configure interfaces for VirtIO network.
# Note that you need to create different tap devices for different VMs.

set TAPDEV="tap0"

# Create bridge and add the NIC. Assume that the NIC is smc0.
ifconfig bridge0 || (ifconfig bridge create; ifconfig bridge0 addm smc0; ifconfig bridge0 inet 10.0.4.1 netmask 255.255.255.0)

# Add the tap device for the VM. Different VMs mut use different tap devices.
ifconfig $TAPDEV create
ifconfig bridge0 addm $TAPDEV
ifconfig $TAPDEV up

ifconfig

echo ""
echo "[Starting sshd]"
echo ""
/usr/sbin/sshd

echo "[Loading kernel module 'vmm']"
echo ""
kldload vmm

echo ""
echo "[Creating VM '$VMNAME' from kernel image: kernel.bin]"
echo ""
bhyveload -k kernel.bin $VMNAME

set CONS_SOCK="/root/console_${VMNAME}.skt"
rm -f "${CONS_SOCK}"

echo "[Starting VM '$VMNAME' with: bvmconsole, virtio-blk, virtio-net, virtio-console, virtio-rnd]"
echo ""
bhyve	\
	-e 0x80000000UL \
	-m 128MB \
	-s '0x200@0x7000#24:virtio-blk,virtio.img' \
	-s "0x200@0x6000#23:virtio-net,${TAPDEV}" \
	-s "0x200@0x5000#22:virtio-console,sock=${CONS_SOCK}" \
	-s '0x200@0x4000#-1:virtio-rnd' \
	-b $VMNAME
