#!/usr/bin/env python3

import subprocess
import os.path

MTREE = 'metalog_backups/host_small.mtree'
WORKSPACE = '/usr/home/alex/arm64-workspace'
ODIR = '/usr/home/alex/arm64-workspace/obj/usr/home/alex/arm64-workspace/freebsd/arm64.aarch64'
FIND_ODIR = 'find ' + ODIR + ' -type f -name '
FIND_HOST_FILES = 'find ' + WORKSPACE + '/files_host -type f -name '

with open(MTREE, 'r') as mtree:
    for line in mtree:
        line = line.split()
        if not line:
            continue

        new_entry = []
        filename = ''
        ignore_line = False
        is_file = False
        for attr in line:
            keyval = attr.split('=')
            if keyval[0] == attr:
                # Save file name.
                basename, filename = os.path.split(attr)
            elif attr == 'type=file':
                is_file = True
            elif keyval[0] == 'size':
                if int(keyval[1]) == 0:
                    # Don't add files of size 0.
                    ignore_line = True
                    break
                else:
                    continue
            elif keyval[0] == 'time':
                # Don't save the 'time' attribute in the mtree file.
                continue
            elif keyval[0] == 'tags':
                # Having the attribute 'tags' will cause a warning, ignore it.
                continue

            new_entry.append(attr)

        if ignore_line:
            continue

        if is_file:
            location_found = False
            output = subprocess.check_output(FIND_ODIR + filename,
                    shell=True)
            if output:
                output = output.decode('utf-8').split('\n')
                for location in output:
                    location = location.strip()
                    if not location:
                        continue
                    if 'tmp' in location:
                        continue
                    if 'FOUNDATION_GUEST' in location:
                        continue
                    location_found = True
                    location = location[location.find(ODIR) + len(ODIR):]
                    location = '"${OBJDIR}' + location + '"'
                    new_entry.append('contents=' + location)
            if not location_found:
                output = subprocess.check_output(FIND_HOST_FILES + filename,
                        shell=True)
                location = output.decode('utf-8').strip()
                location = location[location.find(WORKSPACE) + len(WORKSPACE):]
                if location:
                    location = '"${WORKSPACE}' + location + '"'
                    new_entry.append('contents=' + location)
                else:
                    # Cannot find the file, don't add it.
                    ignore_line = True

        if not ignore_line:
            new_entry = ' '.join(new_entry)
            print(new_entry)

print()
print('./root/payload.bin type=file mode=755 contents="${PAYLOAD}"')
print('./payload.bin type=link mode=755 link=/root/payload.bin')
print('./virtio_run.sh type=link mode=755 link=/root/virtio_run.sh')
print('./virtio.img type=link mode=755 link=/root/virtio.img')

mtree.close()
