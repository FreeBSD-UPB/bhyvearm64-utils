#!/bin/sh -v

ls -l

ifconfig vtnet0 inet 10.0.4.2 netmask 255.255.255.0
ping -c 3 10.0.4.1

ls -l /dev

mount -o rw /dev/vtbd0 /mnt
mount

ls -l /mnt

cat /mnt/virtio_test_file
echo 'test' > /mnt/another_test_file
ls -l /mnt

umount /mnt

mount -o rw /dev/vtbd0 /mnt
mount

ls -l /mnt

cat /mnt/another_test_file
umount /mnt
