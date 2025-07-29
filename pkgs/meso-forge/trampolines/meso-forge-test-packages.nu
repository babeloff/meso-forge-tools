#!/usr/bin/env nu

# Wrapper script for meso-forge-test-packages that properly forwards arguments
def main [...script_args: string] {
    let script_path = ($env.CONDA_PREFIX + "/share/meso-forge/scripts/test_packages.nu")

    # Execute the test_packages script with all passed arguments
    exec nu $script_path ...$script_args
}
