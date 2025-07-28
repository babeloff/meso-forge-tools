#!/usr/bin/env nu

# Update versions in recipe.yaml files
#
# This script provides a Nu shell interface to the Python version control system
# for updating package versions in recipe.yaml files.

def main [
    --package (-p): string          # Update specific package only
    --force (-f)                    # Force update even if version seems current
    --each (-e)                     # Update each package individually
    --list (-l)                     # List all packages that can be updated
    --dry-run (-d)                  # Show what would be updated without making changes
    --recipes-dir (-r): string      # Directory containing recipe files (default: pkgs)
    --help (-h)                     # Show help information
] {
    if $help {
        print "Update versions in recipe.yaml files"
        print ""
        print "Usage:"
        print "  update_versions.nu [OPTIONS]"
        print ""
        print "Options:"
        print "  -p, --package <NAME>        Update specific package only"
        print "  -f, --force                 Force update even if version seems current"
        print "  -e, --each                  Update each package individually"
        print "  -l, --list                  List all packages that can be updated"
        print "  -d, --dry-run               Show what would be updated without making changes"
        print "  -r, --recipes-dir <DIR>     Directory containing recipe files (default: pkgs)"
        print "  -h, --help                  Show this help message"
        print ""
        print "Examples:"
        print "  update_versions.nu --list                    # List all packages"
        print "  update_versions.nu --package python-foo      # Update specific package"
        print "  update_versions.nu --each                    # Update all packages"
        print "  update_versions.nu --dry-run                 # Preview updates"
        print "  update_versions.nu --force --package bar     # Force update specific package"
        return
    }

    # Build command arguments for the Python script
    mut cmd_args = []

    # Set recipes directory
    let recipes_dir = if ($recipes_dir | is-empty) { "pkgs" } else { $recipes_dir }
    $cmd_args = ($cmd_args | append ["--recipes-dir", $recipes_dir])

    # Add specific operation flags
    if $list {
        $cmd_args = ($cmd_args | append "--list-packages")
    } else if $each {
        $cmd_args = ($cmd_args | append ["--update", "--each"])
    } else if not ($package | is-empty) {
        $cmd_args = ($cmd_args | append ["--update", "--package", $package])
    } else {
        # Default to updating all packages
        $cmd_args = ($cmd_args | append ["--update", "--each"])
    }

    # Add modifier flags
    if $force {
        $cmd_args = ($cmd_args | append "--force")
    }

    if $dry_run {
        $cmd_args = ($cmd_args | append "--dry-run")
    }

    # Execute the Python version control script
    try {
        ^python meso-forge/scripts/version_ctl.py ...$cmd_args
    } catch { |e|
        print $"Error running version control: ($e.msg)"
        exit 1
    }
}
