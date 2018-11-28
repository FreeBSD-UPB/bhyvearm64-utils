#!/usr/bin/env python3

import argparse
import json
import os
import pprint
import subprocess
import sys

from pathlib import Path


def resolve_path(pathname, config, is_dir, required=False, must_exist=False):
    if pathname not in config:
        if required:
            sys.exit("Missing argument '%s'" % pathname)
        else:
            return

    config[pathname] = Path(config[pathname]).absolute()
    if must_exist and not config[pathname].exists():
        sys.exit("%s location '%s' must exist" \
                % (pathname, config[pathname]))

    if is_dir:
        if config[pathname].exists() and not config[pathname].is_dir():
            # Path points to file and not directory.
            sys.exit("%s location '%s' is not a directory" \
                    % (pathname, config[pathname]))
        if not config[pathname].exists():
            # Create directory paths.
            config[pathname].mkdir(mode=0o777, parents=True)


def make_buildworld(config):
    make_cmd = [
            'make',
            '-j' + str(config['ncpu']),
            'TARGET=' + config['target'],
            'TARGET_ARCH=' + config['target_arch'],
            config['make_args'],
            'buildworld'
    ]
    subprocess.check_call(make_cmd, cwd=config['src'])


def make_installworld(config):
    if config['target'] == 'arm64':
        sys.exit('Installworld not implemented for architecture: arm64')
    make_cmd = [
            'make',
            '-j' + str(config['ncpu']),
            'DESTDIR=' + str(config['rootfs']),
            config['make_args'],
            'installworld'
    ]
    if config['no_root'] == 'yes':
        make_cmd.insert(len(make_cmd)-1, '-DNO_ROOT')
    subprocess.check_call(make_cmd, cwd=config['src'])


def create_ramdisk(config):
    resolve_path('ramdisk_dir', config, is_dir=True,
            required=True, must_exist=True)
    resolve_path('ramdisk_file', config, is_dir=False,
            required=True)
    resolve_path('ramdisk_mtree', config, is_dir=False,
            required=True, must_exist=True)

    if config['ramdisk_file'].exists():
        subprocess.check_call(['rm', config['ramdisk_file']],
                cwd=config['ramdisk_dir'])

    makefs_cmd = [
            'makefs',
            '-t', 'ffs',
            '-B', 'little',
            '-o', 'optimization=space',
            '-o', 'version=1',
            config['ramdisk_file'],
            config['ramdisk_mtree']
    ]
    subprocess.check_call(makefs_cmd, cwd=config['ramdisk_dir'])


def make_buildkernel(config):
    if config['with_ramdisk'] == 'yes':
        create_ramdisk(config)
    make_cmd = [
            'make',
            '-j' + str(config['ncpu']),
            config['make_args'],
            'buildkernel'
    ]
    if 'kernconf' in config:
        make_cmd.insert(len(make_cmd)-1, 'KERNCONF=' + config['kernconf'])
    subprocess.check_call(make_cmd, cwd=config['src'])


def make_installkernel(config):
    if config['target'] == 'arm64':
        sys.exit('Installkernel not implemented for architecture: arm64')
    make_cmd = [
            'make',
            '-j' + str(config['ncpu']),
            'DESTDIR=' + str(config['rootfs']),
            config['make_args'],
            'installkernel'
    ]
    if config['no_root'] == 'yes':
        make_cmd.insert(len(make_cmd)-1, '-DNO_ROOT')
    if 'kernconf' in config:
        make_cmd.insert(len(make_cmd)-1, 'KERNCONF=' + config['kernconf'])
    subprocess.check_call(make_cmd, cwd=config['src'])


def make_distribution(config):
    if config['target'] == 'arm64':
        sys.exit('Distribution not implemented for architecture: arm64')
    make_cmd = [
            'make',
            '-j' + str(config['ncpu']),
            'DESTDIR=' + str(config['rootfs']),
            config['make_args'],
            'distribution'
    ]
    if config['no_root'] == 'yes':
        make_cmd.insert(len(make_cmd)-1, '-DNO_ROOT')
    subprocess.check_call(make_cmd, cwd=config['src'])


def get_new_env(config):
    new_env = {
            'SRC'       : config['src'],
            'WORKSPACE' : config['workspace'],
            'MAKEOBJDIRPREFIX': config['makeobjdirprefix'],
            'MAKESYSPATH': config['makesyspath'],
            'OBJDIR': config['objdir'],
    }
    if config['with_meta_mode'] == 'yes':
        new_env['WITH_META_MODE'] = 'YES'
    if 'rootfs' in config:
        new_env['ROOTFS'] = config['rootfs']
    new_env = {var: str(val) for var, val in new_env.items()}
    return new_env


targets = [
        'arm64',
        'amd64'
]
# Keep this logically sorted: build targets that depend on other build
# targets should come last.
build_targets = [
        'buildworld',
        'installworld',
        'buildkernel',
        'installkernel',
        'distribution'
]
build_funcs = {
        'buildworld'    : make_buildworld,
        'installworld'  : make_installworld,
        'buildkernel'   : make_buildkernel,
        'installkernel' : make_installkernel,
        'distribution'  : make_distribution
}


def main(args):
    if args.config is not None:
        with open(args.config, 'r') as f:
            config = json.load(f)
    else:
        config = dict()
    # Overwrite build configuration with user arguments.
    for argname, argval in vars(args).items():
        if argval is not None:
            config[argname] = argval

    if 'target' not in config:
        sys.exit('Target architecture is missing; please specify a --target parameter')
    if config['target'] not in targets:
        sys.exit("Unsupported target architecture '%s'" % config['target'])
    if config['target'] == 'amd64':
        config['target_arch'] = 'amd64'
    if config['target'] == 'arm64':
        config['target_arch'] = 'aarch64'

    if 'build' not in config:
        sys.exit('Build target is missing; please specify a --build parameter')
    config['build'] = list(config['build'].split(','))
    config['build'] = list(map(str.strip, config['build']))
    for build_target in config['build']:
        if build_target not in build_targets:
            sys.exit("Unknown build target '%s'" % build_target)

    resolve_path('src', config, is_dir=True, required=True, must_exist=True)
    resolve_path('makeobjdirprefix', config, is_dir=True, required=True)
    if 'workspace' not in config:
        config['workspace'] = Path(__file__).absolute()
    resolve_path('workspace', config, is_dir=True)
    resolve_path('rootfs', config, is_dir=True)

    config['objdir'] = "%s/%s/%s.%s" \
            % (config['makeobjdirprefix'], config['src'], \
            config['target'], config['target_arch'])
    resolve_path('objdir', config, is_dir=True)

    config['makesyspath'] = config['src'] / 'share' / 'mk'
    resolve_path('makesyspath', config, is_dir=True, must_exist=True)

    if 'ncpu' not in config:
        config['ncpu'] = os.cpu_count()

    if config['make_args'] is None:
        config['make_args'] = ''
    if config['no_clean'] == 'yes':
        config['make_args'] += ' -DNO_CLEAN'

    new_env = get_new_env(config)
    os.environ.update(new_env)

    print("\nBuild configuration:\n")
    pprint.pprint(config)
    print("\nNew environment:\n")
    pprint.pprint(new_env)
    print("\n" + '-' * 69 + "\n")

    for build_target in build_targets:
        if build_target in config['build']:
            build_funcs[build_target](config)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--target', help='Target hardware platform',
            choices=targets)
    parser.add_argument('--build',
            help='Targets for the build system. Multiple comma-separated targets can be specified')
    parser.add_argument('--ncpu', help='Number of cpus', type=int)
    parser.add_argument('--kernconf', help='Kernel configuration file name')
    parser.add_argument('--rsync_target', help='Destination directory for rsync')
    parser.add_argument('--src', help='Source directory')
    parser.add_argument('--workspace', help='Workspace directory')
    parser.add_argument('--makeobjdirprefix', help='Object directory')
    parser.add_argument('--rootfs',
            help='Destination directory used by installworld, distribution, installkernel build targets')
    parser.add_argument('--make_args',
            help='Extra arguments to pass to make during all stages')
    parser.add_argument('--ramdisk_dir', help='Ramdisk directory')
    parser.add_argument('--ramdisk_file', help='Ramdisk file name')
    parser.add_argument('--ramdisk_mtree', help='Ramdisk mtree file name')
    yes_no = ['yes', 'no']
    parser.add_argument('--no_clean', help='Build with -DNO_CLEAN',
            choices=yes_no)
    parser.add_argument('--no_root', help='Install without using root privilege',
            choices=yes_no)
    parser.add_argument('--with_meta_mode',
            help='Build with WITH_META_MODE=YES. The filemon module must be loaded',
            choices=yes_no)
    parser.add_argument('--with_ramdisk',
            help='Create a ramdisk when building the kernel', choices=yes_no)
    parser.add_argument('-c', '--config', help='Configuration file in JSON format')

    args = parser.parse_args()
    main(args)
