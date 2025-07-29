#!/usr/bin/env nu

# Wrapper script for meso-forge-pixi-analyze that properly forwards arguments
def main [...script_args: string] {
    let script_path = ($env.CONDA_PREFIX + "/share/meso-forge/scripts/pixi_tasks_manage.nu")

    # Execute the pixi_tasks_manage script with 'analyze' command and all passed arguments
    exec nu $script_path "analyze" ...$script_args
}
