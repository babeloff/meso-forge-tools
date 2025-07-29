#!/usr/bin/env nu

# Wrapper script for meso-forge-build-platform that properly forwards arguments
def main [...script_args: string] {
    let script_path = ($env.CONDA_PREFIX + "/share/meso-forge/scripts/build_platform.nu")

    # Execute the build_platform script with all passed arguments
    exec nu $script_path ...$script_args
}
