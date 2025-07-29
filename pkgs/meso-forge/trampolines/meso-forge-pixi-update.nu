#!/usr/bin/env nu

# Wrapper script for meso-forge-pixi-update that properly forwards arguments
def main [...script_args: string] {
    let script_path = ($env.CONDA_PREFIX + "/share/meso-forge/scripts/pixi_tasks_manage.nu")

    # Execute the pixi_tasks_manage script with 'update' command and all passed arguments
    exec nu $script_path "update" ...$script_args
}
