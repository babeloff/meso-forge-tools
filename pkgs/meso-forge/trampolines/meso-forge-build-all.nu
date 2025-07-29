#!/usr/bin/env nu

# Wrapper script for meso-forge-build-all that properly forwards arguments
def main [...script_args: string] {
    let script_path = ($env.CONDA_PREFIX + "/share/meso-forge/scripts/build_all.nu")

    # Execute the build_all script with all passed arguments
    exec nu $script_path ...$script_args
}
