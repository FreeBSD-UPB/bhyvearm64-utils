#!/usr/bin/env python3.7

import argparse
import json
import os
import pprint
import subprocess
import sys

from pathlib import Path


_interactive = True


def resolve_path(pathname, config, is_dir, required=False, must_exist=False):
    if required:
        if pathname not in config:
            sys.exit("Missing argument '%s'" % pathname)
        if not config[pathname]:
            # Empty path resolves to current directory. We don't want that.
            sys.exit("Empty argument '%s'" % pathname)

    if pathname not in config:
        return
    if not config[pathname]:
        # Delete empty pathname, it is not resolved to a Path object and it will
        # cause a lot of pain if it is used later.
        # Invoking the script with an empty from from the command line can be
        # used to remove paths set in the configuration file, if present.
        del config[pathname]
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
    else:
        if config[pathname].exists() and not config[pathname].is_file():
            sys.exit("%s location '%s' is not a file" \
                    % (pathname, config[pathname]))


def command(cmd, **kwargs):
    if _interactive:
        cmd_str = ' '.join(map(str, cmd))
        print()
        print("Running command: '%s'" % cmd_str)
        if kwargs:
            print('Extra arguments: %s' % str(kwargs))
        input('Press any key to continue...')
    subprocess.check_call(cmd, **kwargs)


def make_buildworld(config):
    make_cmd = [
            'make',
            '-j' + str(config['ncpu']),
            'TARGET=' + config['target'],
            'TARGET_ARCH=' + config['target_arch'],
            config['make_args'],
            'buildworld'
    ]
    command(make_cmd, cwd=config['src'])


def make_installworld(config):
    if config['target'] == 'arm64':
        sys.exit('Installworld not implemented for architecture: arm64')
    make_cmd = [
            'make',
            '-j' + str(config['ncpu']),
            config['make_args'],
            'installworld'
    ]
    if config['no_root'] == 'yes':
        make_cmd.insert(len(make_cmd)-1, '-DNO_ROOT')
    if 'rootfs' in config:
        make_cmd.insert(len(make_cmd)-1, 'DESTDIR=' + str(config['rootfs']))
    command(make_cmd, cwd=config['src'])


def create_ramdisk(config):
    resolve_path('ramdisk_dir', config, is_dir=True,
            required=True, must_exist=True)
    resolve_path('ramdisk_file', config, is_dir=False,
            required=True)
    resolve_path('ramdisk_mtree', config, is_dir=False,
            required=True, must_exist=True)

    if config['ramdisk_file'].exists():
        command(['rm', config['ramdisk_file']],
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
    command(makefs_cmd, cwd=config['ramdisk_dir'])


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
    command(make_cmd, cwd=config['src'])


def make_installkernel(config):
    if config['target'] == 'arm64':
        sys.exit('Installkernel not implemented for architecture: arm64')
    make_cmd = [
            'make',
            '-j' + str(config['ncpu']),
            config['make_args'],
            'installkernel'
    ]
    if config['no_root'] == 'yes':
        make_cmd.insert(len(make_cmd)-1, '-DNO_ROOT')
    if 'kernconf' in config:
        make_cmd.insert(len(make_cmd)-1, 'KERNCONF=' + config['kernconf'])
    if 'rootfs' in config:
        make_cmd.insert(len(make_cmd)-1, 'DESTDIR=' + str(config['rootfs']))
    command(make_cmd, cwd=config['src'])


def make_distribution(config):
    if config['target'] == 'arm64':
        sys.exit('Distribution not implemented for architecture: arm64')
    make_cmd = [
            'make',
            '-j' + str(config['ncpu']),
            config['make_args'],
            'distribution'
    ]
    if config['no_root'] == 'yes':
        make_cmd.insert(len(make_cmd)-1, '-DNO_ROOT')
    if 'rootfs' in config:
        make_cmd.insert(len(make_cmd)-1, 'DESTDIR=' + str(config['rootfs']))
    command(make_cmd, cwd=config['src'])


def get_new_env(config):
    new_env = {
            'SRC'       : config['src'],
            'WORKSPACE' : config['workspace'],
            'MAKEOBJDIRPREFIX': config['makeobjdirprefix'],
            'MAKESYSPATH': config['makesyspath'],
            'OBJDIR'    : config['objdir'],
            'TARGET'    : config['target'],
            'TARGET_ARCH': config['target_arch']
    }
    if config['with_meta_mode'] == 'yes':
        new_env['WITH_META_MODE'] = 'YES'
    if 'rootfs' in config:
        new_env['ROOTFS'] = config['rootfs']
    if config['with_ramdisk'] == 'yes':
        new_env['RAMDISK_DIR'] = config['ramdisk_dir']
    new_env = {var: str(val) for var, val in new_env.items()}

    return new_env


def get_config(args, yesno_argnames):
    if args.config is not None:
        with open(args.config, 'r') as f:
            config = json.load(f)
    else:
        config = dict()

    # Override config values with arguments.
    for argname, argval in vars(args).items():
        if argval is None:
            if argname in yesno_argnames and argname not in config:
                # Replace empty (equal to None) yes/no arguments with 'no'.
                config[argname] = 'no'
            else:
                # All other empty arguments are discarded.
                pass
        else:
            config[argname] = argval
    return config


targets = [
        'arm64',
        'amd64'
]


def main(args, yesno_argnames):
    global _interactive

    config = get_config(args, yesno_argnames)

    if 'build' not in config or not config['build']:
        sys.exit('Missing build target; please specify a --build parameter')

    if config['interactive'] == 'no':
        _interactive = False

    if 'target' not in config:
        sys.exit('Target architecture is missing; please specify a --target parameter')
    if config['target'] not in targets:
        sys.exit("Unsupported target architecture '%s'" % config['target'])
    if config['target'] == 'amd64':
        config['target_arch'] = 'amd64'
    if config['target'] == 'arm64':
        config['target_arch'] = 'aarch64'

    config['build'] = list(config['build'].split(','))
    config['build'] = list(map(str.strip, config['build']))

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
    if _interactive:
        input('Press any key to continue...')

    build_funcs = {
            'buildworld'    : make_buildworld,
            'installworld'  : make_installworld,
            'buildkernel'   : make_buildkernel,
            'installkernel' : make_installkernel,
            'distribution'  : make_distribution
    }

    for k, build_target in enumerate(config['build']):
        if build_target in build_funcs:
            if build_target == 'installworld' \
                    and 'buildworld' in config['build'][k+1:]:
                print('installworld build target comes before buildworld target')
                input('Press any key to continue...')
            if build_target == 'installkernel' \
                    and 'buildkernel' in config['build'][k+1:]:
                print('installkernel build target comes before buildkernel target')
                input('Press any key to continue...')
            build_funcs[build_target](config)
        else:
            make_cmd = [
                    'make',
                    '-j' + str(config['ncpu']),
                    config['make_args'],
                    build_target
            ]
            if config['no_root'] == 'yes':
                make_cmd.insert(len(make_cmd)-1, '-DNO_ROOT')
            if 'rootfs' in config:
                make_cmd.insert(len(make_cmd)-1, 'DESTDIR=' + str(config['rootfs']))
            if 'kernconf' in config:
                make_cmd.insert(len(make_cmd)-1, 'KERNCONF=' + config['kernconf'])
            command(make_cmd, cwd=config['src'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--target', help='Target hardware platform',
            choices=targets)
    parser.add_argument('--build',
            help='Targets for the build system. Multiple comma-separated targets can be specified')
    parser.add_argument('--ncpu', help='Number of cpus', type=int)
    parser.add_argument('--kernconf', help='Kernel configuration file name')
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
    parser.add_argument('-i', '--interactive',
            help='Wait for user input before executing commands',
            choices=yes_no)
    parser.add_argument('--no_clean', help='Build with -DNO_CLEAN',
            choices=yes_no)
    parser.add_argument('--no_root', help='Install without using root privilege',
            choices=yes_no)
    parser.add_argument('--with_meta_mode',
            help='Build with WITH_META_MODE=YES. The filemon module must be loaded',
            choices=yes_no)
    parser.add_argument('--with_ramdisk',
            help='Create a ramdisk when building the kernel',
            choices=yes_no)
    yesno_argnames = ['interactive', 'no_clean', 'no_root', 'with_meta_mode',
            'with_ramdisk']
    parser.add_argument('-c', '--config', help='Configuration file in JSON format')

    args = parser.parse_args()
    main(args, yesno_argnames)
