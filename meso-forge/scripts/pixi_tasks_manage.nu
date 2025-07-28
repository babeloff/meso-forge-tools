#!/usr/bin/env nu

# Pixi Task Manager for Meso-forge
# This script provides a unified interface to analyze and update meso-forge tasks in pixi.toml files

use std log
use ./pixi_tasks_mod.nu *

def main [
    command: string                        # Command to execute: analyze, update, or help
    --pixi-file: string = "pixi.toml"     # Path to the pixi.toml file
    --dry-run                             # Show what would be changed without making changes (update only)
    --verbose                             # Enable verbose logging
    --show-all                            # Show all tasks, not just meso-forge ones (analyze only)
    --force                               # Force update without confirmation
] {
    match $command {
        "analyze" => { analyze_tasks $pixi_file $verbose $show_all }
        "update" => { update_tasks $pixi_file $dry_run $verbose $force }
        "help" => { show_help }
        _ => {
            print $"Error: Unknown command '($command)'"
            print "Use 'help' to see available commands"
            exit 1
        }
    }
}

# Analyze meso-forge tasks in pixi.toml
def analyze_tasks [pixi_file: string, verbose: bool, show_all: bool] {
    if $verbose {
        log info "Starting pixi.toml analysis"
    }

    # Load and validate pixi file
    let pixi_data = load_pixi_file $pixi_file

    # Get expected and current tasks
    let expected_tasks = get_meso_forge_tasks
    let current_tasks = get_current_tasks $pixi_data

    print $"=== Pixi.toml Analysis: ($pixi_file) ==="
    print ""

    # Analyze task status
    let analysis = analyze_task_status $current_tasks $expected_tasks

    # Display summary
    print (format_task_summary $analysis ($expected_tasks | length))

    # Display missing tasks
    if ($analysis.missing | length) > 0 {
        print "❌ **Missing Meso-forge Tasks:**"
        for task in $analysis.missing {
            print $"  - ($task)"
        }
        print ""
    }

    # Display outdated tasks
    if ($analysis.outdated | length) > 0 {
        print "⚠️  **Outdated Meso-forge Tasks:**"
        for task in $analysis.outdated {
            print $"  - ($task)"
        }
        print ""
    }

    # Display up-to-date tasks
    if ($analysis.up_to_date | length) > 0 and ($analysis.outdated | length) == 0 {
        print "✅ **Up-to-date Meso-forge Tasks:**"
        for task in $analysis.up_to_date {
            print $"  - ($task)"
        }
        print ""
    }

    # Display other tasks if requested
    if $show_all and ($analysis.other | length) > 0 {
        print "🔧 **Other Tasks:**"
        for task in $analysis.other {
            let cmd_preview = if ($task.config | get cmd? | default "" | describe) == "list" {
                $task.config.cmd | str join " " | str substring 0..50
            } else {
                $task.config.cmd | str substring 0..50
            }
            print $"  - ($task.name): ($cmd_preview)..."
        }
        print ""
    }

    # Configuration differences for outdated tasks
    if $verbose and ($analysis.outdated | length) > 0 {
        print "🔍 **Configuration Differences:**"
        for task_name in $analysis.outdated {
            print $"  **($task_name):**"
            let current = $current_tasks | where name == $task_name | get config.0
            let expected = $expected_tasks | where name == $task_name | get config.0

            print "    Current:"
            let current_yaml = $current | to yaml | lines | each {|line| $"      ($line)"} | str join (char newline)
            print $current_yaml
            print "    Expected:"
            let expected_yaml = $expected | to yaml | lines | each {|line| $"      ($line)"} | str join (char newline)
            print $expected_yaml
            print ""
        }
    }

    # Display recommendations
    print (format_recommendations $analysis $pixi_file)
}

# Update meso-forge tasks in pixi.toml
def update_tasks [pixi_file: string, dry_run: bool, verbose: bool, force: bool] {
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
        # Confirm changes unless force is used
        if not $force {
            print ""
            print "This will modify your pixi.toml file."
            if ($added_tasks | length) > 0 {
                print $"- Adding ($added_tasks | length) new tasks"
            }
            if ($updated_tasks_list | length) > 0 {
                print $"- Updating ($updated_tasks_list | length) existing tasks"
            }
            print ""
            let confirm = input "Continue? (y/N): "
            if $confirm != "y" and $confirm != "Y" {
                print "Operation cancelled"
                return
            }
        }

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

# Show help information
def show_help [] {
    print "Pixi Task Manager for Meso-forge"
    print ""
    print "USAGE:"
    print "  nu pixi_tasks_manage.nu <COMMAND> [OPTIONS]"
    print ""
    print "COMMANDS:"
    print "  analyze   Analyze current meso-forge tasks in pixi.toml"
    print "  update    Update pixi.toml with latest meso-forge task definitions"
    print "  help      Show this help message"
    print ""
    print "OPTIONS:"
    print "  --pixi-file <PATH>    Path to pixi.toml file (default: pixi.toml)"
    print "  --verbose             Enable verbose logging"
    print ""
    print "ANALYZE OPTIONS:"
    print "  --show-all            Show all tasks, not just meso-forge ones"
    print ""
    print "UPDATE OPTIONS:"
    print "  --dry-run             Show changes without applying them"
    print "  --force               Skip confirmation prompt"
    print ""
    print "EXAMPLES:"
    print "  # Analyze current tasks"
    print "  nu pixi_tasks_manage.nu analyze"
    print ""
    print "  # Preview what would be updated"
    print "  nu pixi_tasks_manage.nu update --dry-run"
    print ""
    print "  # Update tasks with confirmation"
    print "  nu pixi_tasks_manage.nu update"
    print ""
    print "  # Force update without confirmation"
    print "  nu pixi_tasks_manage.nu update --force"
    print ""
    print "  # Work with a different pixi.toml file"
    print "  nu pixi_tasks_manage.nu analyze --pixi-file ../other-project/pixi.toml"
}
