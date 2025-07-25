#!/usr/bin/env nu

# Update pixi.toml with meso-forge-tooling related tasks
# This script can add or replace meso-forge-tooling tasks in a pixi.toml file

use std log
use pixi_tasks_mod.nu *

def main [
    --pixi-file: string = "pixi.toml"  # Path to the pixi.toml file to update
    --dry-run                          # Show what would be changed without making changes
    --verbose                          # Enable verbose logging
] {
    if $verbose {
        log info "Starting pixi.toml update process"
    }

    # Load and validate pixi file
    let pixi_data = load_pixi_file $pixi_file

    # Get meso-forge tasks and current tasks
    let meso_forge_tasks = get_meso_forge_tasks
    let current_tasks = get_current_tasks $pixi_data

    if $verbose {
        log info $"Found ($meso_forge_tasks | length) meso-forge tasks to process"
    }

    # Get existing tasks section
    let tasks_section = if "tasks" in $pixi_data {
        $pixi_data.tasks
    } else {
        {}
    }

    # Process each task and track changes
    let task_updates = $meso_forge_tasks | each {|task|
        let task_name = $task.name
        let task_config = $task.config

        let status = if $task_name in $tasks_section {
            "updated"
        } else {
            "added"
        }

        {
            name: $task_name
            config: $task_config
            status: $status
        }
    }

    # Create updated tasks section
    let updated_tasks = create_updated_tasks $tasks_section $meso_forge_tasks

    # Create updated pixi data
    let updated_pixi_data = $pixi_data | upsert tasks $updated_tasks

    # Extract added and updated task lists
    let added_tasks = $task_updates | where status == "added" | get name
    let updated_tasks_list = $task_updates | where status == "updated" | get name

    # Report changes
    if ($added_tasks | length) > 0 {
        print $"Added tasks: (($added_tasks | str join ', '))"
    }

    if ($updated_tasks_list | length) > 0 {
        print $"Updated tasks: (($updated_tasks_list | str join ', '))"
    }

    if ($added_tasks | length) == 0 and ($updated_tasks_list | length) == 0 {
        print "No changes needed - all meso-forge tasks are up to date"
        return
    }

    # Convert back to TOML
    let new_content = try {
        $updated_pixi_data | to toml
    } catch {
        log error "Failed to convert data back to TOML"
        exit 1
    }

    if $dry_run {
        print "=== DRY RUN - Changes that would be made ==="
        print $new_content
        print "=== END DRY RUN ==="
    } else {
        # Create backup
        let backup_file = generate_backup_filename $pixi_file
        cp $pixi_file $backup_file
        if $verbose {
            log info $"Created backup: ($backup_file)"
        }

        # Write updated content
        $new_content | save --force $pixi_file
        print $"Successfully updated ($pixi_file)"
        print $"Backup saved as: ($backup_file)"
    }
}
