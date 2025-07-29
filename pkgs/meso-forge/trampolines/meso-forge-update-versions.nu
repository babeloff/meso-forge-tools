#!/usr/bin/env nu

# Wrapper script for meso-forge-update-versions that properly forwards arguments
def main [...script_args: string] {
    let script_path = ($env.CONDA_PREFIX + "/share/meso-forge/scripts/update_versions.nu")

    # Execute the update_versions script with all passed arguments
    exec nu $script_path ...$script_args
}
