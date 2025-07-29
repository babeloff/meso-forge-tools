#!/usr/bin/env nu

# Wrapper script for meso-forge-build-noarch that properly forwards arguments
def main [...script_args: string] {
    let script_path = ($env.CONDA_PREFIX + "/share/meso-forge/scripts/build_noarch.nu")

    # Execute the build_noarch script with all passed arguments
    exec nu $script_path ...$script_args
}
