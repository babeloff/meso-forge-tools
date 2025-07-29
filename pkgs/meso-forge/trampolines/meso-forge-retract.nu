#!/usr/bin/env nu

# Wrapper script for meso-forge-retract that properly forwards arguments
def main [...script_args: string] {
    let script_path = ($env.CONDA_PREFIX + "/share/meso-forge/scripts/package_retract.nu")

    # Execute the package_retract script with all passed arguments
    exec nu $script_path ...$script_args
}
