#!/usr/bin/env nu

# Wrapper script for meso-forge-build-single that properly forwards arguments
def main [--recipe: string, --tgt-dir: string = "./output", --dry-run, --verbose, --force] {
    let script_path = ($env.CONDA_PREFIX + "/share/meso-forge/scripts/build_single.nu")
    mut cmd = ["nu", $script_path]

    if $recipe != null {
        $cmd = ($cmd | append ["--recipe", $recipe])
    }
    if $tgt_dir != "./output" {
        $cmd = ($cmd | append ["--tgt-dir", $tgt_dir])
    }
    if $dry_run {
        $cmd = ($cmd | append "--dry-run")
    }
    if $verbose {
        $cmd = ($cmd | append "--verbose")
    }
    if $force {
        $cmd = ($cmd | append "--force")
    }

    run-external "nu" ...($cmd | skip 1)
}
