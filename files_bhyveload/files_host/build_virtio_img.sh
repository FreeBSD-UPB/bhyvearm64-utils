#!/usr/bin/env bash

makefs -t ffs -B little -o optimization=space -o version=1 -s 1m \
	virtio.img virtio-file.mtree
