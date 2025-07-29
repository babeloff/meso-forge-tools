#!/usr/bin/env nu

# Wrapper script for meso-forge-check-package that properly forwards arguments
def main [...script_args: string] {
    let script_path = ($env.CONDA_PREFIX + "/share/meso-forge/scripts/check_package_exists.nu")

    # Execute the check_package_exists script with all passed arguments
    exec nu $script_path ...$script_args
}
