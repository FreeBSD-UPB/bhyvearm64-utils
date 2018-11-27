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
    if config['target'] == 'amd64':
        print('Installworld not implemented for architecture: amd64')
        return


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
    if config['target'] == 'amd64':
        print('Installkernel not implemented for architecture: amd64')
        return


def make_distribution(config):
    if config['target'] == 'amd64':
        print('Distribution not implemented for architecture: amd64')
        return


build_targets = {
        'buildworld'    : make_buildworld,
        'installworld'  : make_installworld,
        'buildkernel'   : make_buildkernel,
        'installkernel' : make_installkernel,
        'distribution'  : make_distribution
}


def get_new_env(config):
    new_env = {
            'SRC'       : config['src'],
            'WORKSPACE' : config['workspace'],
            'MAKEOBJDIRPREFIX': config['makeobjdirprefix'],
            'ROOTFS'    : config['rootfs'],
            'MAKESYSPATH': config['makesyspath']
    }
    if config['with_meta_mode']:
        new_env['WITH_META_MODE'] = 'YES'
    new_env = {var: str(val) for var, val in new_env.items()}

    return new_env


def main(args):
    if args.config is not None:
        with open(args.config, 'r') as f:
            config = json.load(f)
    else:
        config = dict()
    user_args = dict()
    for argname, argval in vars(args).items():
        if argval is not None:
            user_args[argname] = argval
    # Overwrite build configuration with user arguments.
    config.update(user_args)

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

    config['objdir'] = "%s/%s/%s.%s" \
            % (config['makeobjdirprefix'], config['src'], \
            config['target'], config['target_arch'])
    validate_dir('objdir', config)

    config['makesyspath'] = config['src'] / 'share' / 'mk'
    validate_dir('makesyspath', config, must_exist=True)

    if 'ncpu' not in config:
        config['ncpu'] = os.cpu_count()

    if config['make_args'] is None:
        config['make_args'] = ''
    if config['no_clean']:
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
            if config['skip_steps']:
                # Build target unconditionally.
                build_targets[build_target](config)
            else:
                if build_target == 'installworld' \
                        and 'buildworld' not in config['build']:
                    # Make buildworld before installworld.
                    build_targets['buildworld'](config)
                    build_targets['installworld'](config)
                elif build_target == 'installkernel' \
                        and 'buildkernel' not in config['build']:
                    # Make buildkernel before installkernel.
                    build_targets['buildkernel'](config)
                    build_targets['installkernel'](config)
                else:
                    # No dependency for the target, build it.
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
    yes_no = ['yes', 'no']
    parser.add_argument('--create_disk', help='Create disk image',
            choices=yes_no, default='no')
    parser.add_argument('--do_rsync', help='Use rsync to send disk image',
            choices=yes_no, default='no')
    parser.add_argument('--no_clean', help='Skip intermediate build steps',
            choices=yes_no, default='yes')
    parser.add_argument('--with_meta_mode', help='Compile with WITH_META_MODE=YES',
            choices=yes_no, default='yes')
    parser.add_argument('--skip_steps', help='Skip intermediate build steps',
            choices=yes_no, default='yes')
    parser.add_argument('-c', '--config', help='Configuration file in JSON format')

    args = parser.parse_args()
    # Convert yes/no argument values to True/False.
    args.do_rsync = True if args.do_rsync == 'yes' else False
    args.no_clean = True if args.no_clean == 'yes' else False
    args.with_meta_mode = True if args.with_meta_mode == 'yes' else False
    args.skip_steps = True if args.skip_steps == 'yes' else False

    main(args)
