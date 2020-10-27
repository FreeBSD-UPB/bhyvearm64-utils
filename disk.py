#!/usr/bin/env python3.7

import argparse
import json
import os
import pprint
import subprocess
import sys

from pathlib import Path

import build


def create_disk(config):
    if config['disk'].exists():
        config['disk'].unlink()

    disk_dir = config['disk'].parent
    freebsd_part = disk_dir / 'freebsd_part.img'
    makefs_cmd = [
            'makefs',
            '-D',
            '-t', 'ffs',
            '-B', 'little',
            '-o', 'optimization=space',
            '-o', 'version=1',
            freebsd_part,
            config['mtree']
    ]
    build.command(makefs_cmd, cwd=disk_dir)

    mkimg_cmd = [
            'mkimg',
            '-vvv',
            '-s', 'gpt',
            '-p', 'efi:=' + str(config['efi_img']),
            '-p', 'freebsd:=' + str(freebsd_part),
            '-o', config['disk']
    ]
    build.command(mkimg_cmd, cwd=disk_dir)
    '''
    if config['rsync_target'] is not None:
        rsync_cmd = [
                'rsync',
                '-arPhh',
                config['disk'],
                config['rsync_target'],
                '--checksum'
        ]
        build.command(rsync_cmd)
    '''

def get_new_env(config):
    new_env = {
            'SRC'       : config['src'],
            'WORKSPACE' : config['workspace'],
            'MAKEOBJDIRPREFIX': config['makeobjdirprefix'],
            'OBJDIR'    : config['objdir'],
            'PAYLOAD'   : config['payload'],
            'CUSTOM_DIR': config['custom_dir']
    }
    new_env = {var: str(val) for var, val in new_env.items()}
    return new_env


def main(args, yesno_argnames):
    config = build.get_config(args, yesno_argnames)
    if config['interactive'] == 'no':
        build._interactive = False

    if 'target' not in config:
        sys.exit('Target architecture is missing; please specify a --target parameter')
    if config['target'] not in build.targets:
        sys.exit("Unsupported target architecture '%s'" % config['target'])

    if 'target_arch' not in config:
        if config['target'] == 'amd64':
            config['target_arch'] = 'amd64'
        if config['target'] == 'arm64':
            config['target_arch'] = 'aarch64'

    build.resolve_path('disk', config, is_dir=False, required=True)
    build.resolve_path('mtree', config, is_dir=False,
            required=True, must_exist=True)
    build.resolve_path('src', config, is_dir=True,
            required=True, must_exist=True)
    build.resolve_path('makeobjdirprefix', config, is_dir=True,
            required=True, must_exist=True)
    build.resolve_path('workspace', config, is_dir=True,
            required=True, must_exist=True)
    build.resolve_path('payload', config, is_dir=False,
            required=True, must_exist=True)
    build.resolve_path('custom_dir', config, is_dir=True,
            required=True, must_exist=True)
    config['objdir'] = "%s/%s/%s.%s" \
            % (config['makeobjdirprefix'], config['src'], \
            config['target'], config['target_arch'])
    build.resolve_path('objdir', config, is_dir=True,
            required=True, must_exist=True)

    if 'efi_img' not in config:
    	# Efifat removed from FreeBSD
	# ARMv8
        config['efi_img'] = '/root/reps/bhyvearm64-utils/disk/boot1.efifat'
        print('Using default EFI image at: %s' % str(config['efi_img']))
        if build._interactive:
            input('Press any key to continue...')
    build.resolve_path('efi_img', config, is_dir=False,
            required=True, must_exist=True)

    new_env = get_new_env(config)
    os.environ.update(new_env)

    print("\nBuild configuration:\n")
    pprint.pprint(config)
    print("\nNew environment:\n")
    pprint.pprint(new_env)
    print("\n" + '-' * 69 + "\n")
    if build._interactive:
        input('Press any key to continue...')

    create_disk(config)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--disk', help='Disk name')
    parser.add_argument('--target', help='Target hardware platform',
            choices=build.targets)
    parser.add_argument('--target_arch', help='Target hardware platform')
    parser.add_argument('--mtree',
            help='File name with the file hierarchy for the disk')
    parser.add_argument('--efi_img', help='EFI image file name')
    parser.add_argument('--custom_dir',
            help='Directory for extra files that will be used in the final image')
    parser.add_argument('--payload', help='Payload image for the host')
    parser.add_argument('--makeobjdirprefix', help='Object directory')
    parser.add_argument('--src', help='Source directory')
    parser.add_argument('--workspace', help='Workspace directory')
    parser.add_argument('--rsync_target', help='Destination for the final image')
    parser.add_argument('-c', '--config', help='Configuration file in JSON format')

    yes_no = ['yes', 'no']
    parser.add_argument('--is_metalog',
            help='The mtree file is the result of the installworld commmand',
            choices=yes_no)
    parser.add_argument('-i', '--interactive',
            help='Wait for user input before executing commands',
            choices=yes_no)
    yesno_argnames = ['interactive', 'is_metalog']

    args = parser.parse_args()
    main(args, yesno_argnames)
