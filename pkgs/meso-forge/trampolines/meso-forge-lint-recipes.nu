#!/usr/bin/env nu

# Wrapper script for meso-forge-lint-recipes that properly forwards arguments
def main [...script_args: string] {
    let script_path = ($env.CONDA_PREFIX + "/share/meso-forge/scripts/lint_recipes.nu")

    # Execute the lint_recipes script with all passed arguments
    exec nu $script_path ...$script_args
}
