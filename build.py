#!/usr/bin/env python3

import argparse
import json
import os
import pprint
import subprocess
import sys

from pathlib import Path


targets = [
        'arm64',
        'amd64'
]


def validate_dir(pathname, config, required=False, must_exist=False):
    if pathname not in config:
        if required:
            sys.exit("Missing argument '%s'" % pathname)
        else:
            return

    config[pathname] = Path(config[pathname]).absolute()

    if must_exist and not config[pathname].exists():
        sys.exit("%s location '%s' must exist" \
                % (pathname, config[pathname]))

    if config[pathname].exists():
        if not config[pathname].is_dir():
            sys.exit("%s location '%s' is not a directory" \
                    % (pathname, config[pathname]))
    else:
        config[pathname].mkdir(mode=0o777, parents=True)


def command(cmd, **kwargs):
    # Convert Path objects to strings.
    cmd = list(map(str, cmd))
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
    pass


def make_buildkernel(config):
    if 'kernconf' not in config:
        sys.exit('Kernel configuration file name missing; please specify a --kernconf parameter')
    make_cmd = [
            'make',
            '-j' + str(config['ncpu']),
            'KERNCONF=' + config['kernconf'],
            config['make_args'],
            'buildkernel'
    ]
    command(make_cmd, cwd=config['src'])


def make_installkernel(config):
    pass


def make_distribution(config):
    pass


build_targets = {
        'buildworld'    : make_buildworld,
        'installworld'  : make_installworld,
        'buildkernel'   : make_buildkernel,
        'installkernel' : make_installkernel,
        'distribution'  : make_distribution
}

def main(config):
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

    validate_dir('src', config, required=True, must_exist=True)
    validate_dir('makeobjdirprefix', config, required=True)
    if 'workspace' not in config:
        config['workspace'] = Path(__file__).absolute()
    validate_dir('workspace', config)
    validate_dir('rootfs', config)

    if config['target'] == 'arm64':
        arch_subarch = 'arm64.aarch64'
    elif config['target'] == 'amd64':
        arch_subarch = 'amd64.amd64'
    config['objdir'] = "%s/%s/%s" \
            % (str(config['makeobjdirprefix']), str(config['src']), arch_subarch)
    validate_dir('objdir', config)

    config['makesyspath'] = config['src'] / 'share' / 'mk'
    validate_dir('makesyspath', config, must_exist=True)

    if 'ncpu' not in config:
        config['ncpu'] = os.cpu_count()

    if not config['do_clean']:
        config['make_args'] += ' -DNO_CLEAN'
    if config['make_args'] is None:
        config['make_args'] = ''

    print("\nBuild configuration:\n")
    pprint.pprint(config)

    new_env = {
            'SRC'       : config['src'],
            'WORKSPACE' : config['workspace'],
            'MAKEOBJDIRPREFIX': config['makeobjdirprefix'],
            'ROOTFS'    : config['rootfs'],
            'MAKESYSPATH': config['makesyspath']
    }
    if 'WITH_META_MODE' in config['make_args']:
        new_env['WITH_META_MODE'] = 'YES'
    new_env = {var: str(val) for var, val in new_env.items()}

    print("\nNew environment:\n")
    pprint.pprint(new_env)

    print("\n" + '-' * 69 + "\n")

    os.environ.update(new_env)
    for build_target in config['build']:
        build_targets[build_target](config)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--target', help='Target architecture',
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
    parser.add_argument('--guest_make_args',
            help='Extra arguments to pass to make for building the guest')
    parser.add_argument('--guest', help='Type of guest to build',
            choices=['freebsd'])
    parser.add_argument('--create_disk', help='Create disk image',
            action='store_true')
    parser.add_argument('--do_rsync', help='Use rsync to send disk image',
            action='store_true')
    parser.add_argument('--do_clean', help='Skip intermediate build steps',
            action='store_true')
    parser.add_argument('--skip_steps', help='Skip intermediate build steps',
            action='store_true', default=True)
    parser.add_argument('-c', '--config', help='Configuration file in JSON format')

    args = parser.parse_args()
    if args.config is not None:
        with open(args.config, 'r') as f:
            config = json.load(f)
    user_args = dict()
    for argname, argval in vars(args).items():
        if argval is not None:
            user_args[argname] = argval
    # Overwrite build configuration with user arguments.
    config.update(user_args)
    main(config)
