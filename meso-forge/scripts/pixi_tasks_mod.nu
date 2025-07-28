#!/usr/bin/env nu

# Pixi Task Manager for Meso-forge
# This script provides a unified interface to analyze and update meso-forge tasks in pixi.toml files
# Also contains shared functionality used by analyze, update, and manage scripts
#
# Task Implementation Options:
# 1. Direct nushell scripts (default): Uses "nu meso-forge/scripts/*.nu"
# 2. Trampoline scripts (alternative): Uses "meso-forge-*" command wrappers
#
# The direct script approach is recommended for better performance and compatibility

use std log

# Get all meso-forge task definitions with their complete configurations
# Uses direct nushell script calls for better compatibility and performance
export def get_meso_forge_tasks [] {
    [
        # Build tasks
        {
            name: "build-all"
            config: {
                cmd: ["nu", "meso-forge/scripts/build_all.nu"]
                cwd: "."
            }
        }
        {
            name: "build-noarch"
            config: {
                cmd: ["nu", "meso-forge/scripts/build_noarch.nu"]
                cwd: "."
            }
        }
        {
            name: "build-platform"
            config: {
                cmd: ["nu", "meso-forge/scripts/build_platform.nu"]
                cwd: "."
            }
        }
        {
            name: "build-all-platforms"
            config: {
                cmd: ["nu", "meso-forge/scripts/build_platform.nu", "--all-platforms"]
                cwd: "."
            }
        }
        {
            name: "build-for-platform"
            config: {
                args: [
                    {arg: "platform", default: "linux-64"}
                ]
                cmd: ["nu", "meso-forge/scripts/build_platform.nu", "--platform", "{{ platform }}"]
                cwd: "."
            }
        }

        {
            name: "build-pkg"
            config: {
                args: [
                    {arg: "pkg", default: "asciidoctor-revealjs"}
                ]
                cmd: ["nu", "meso-forge/scripts/build_single.nu", "--recipe", "pkgs/{{ pkg }}/recipe.yaml"]
                cwd: "."
            }
        }
        {
            name: "build-dry"
            config: {
                args: [
                    {arg: "pkg", default: "asciidoctor-revealjs"}
                ]
                cmd: ["nu", "meso-forge/scripts/build_single.nu", "--recipe", "pkgs/{{ pkg }}/recipe.yaml", "--dry-run"]
                cwd: "."
            }
        }

        # Lint tasks
        {
            name: "lint-recipes"
            config: {
                cmd: ["nu", "meso-forge/scripts/lint_recipes.nu"]
                cwd: "."
            }
        }
        {
            name: "lint-recipes-fix"
            config: {
                cmd: ["nu", "meso-forge/scripts/lint_recipes.nu", "--fix"]
                cwd: "."
            }
        }

        # Test tasks
        {
            name: "test-packages"
            config: {
                cmd: ["nu", "meso-forge/scripts/test_packages.nu"]
                cwd: "."
            }
        }
        {
            name: "test-platform"
            config: {
                cmd: ["nu", "meso-forge/scripts/test_packages.nu", "--platform"]
                cwd: "."
            }
        }
        {
            name: "test-package"
            config: {
                cmd: ["nu", "meso-forge/scripts/test_packages.nu", "--package"]
                cwd: "."
            }
        }

        # Publishing tasks
        {
            name: "publish-pd"
            config: {
                args: [
                    {arg: "force", default: ""}
                    {arg: "channel", default: "meso-forge"}
                ]
                cwd: "."
                cmd: [
                    "nu",
                    "meso-forge/scripts/package_publish.nu",
                    "--mode", "pd",
                    "--channel", "{{ channel }}",
                    "{{ '--force' if force != '' else '' }}"
                ]
            }
        }
        {
            name: "publish-s3"
            config: {
                args: [
                    {arg: "force", default: ""}
                    {arg: "dry_run", default: ""}
                    {arg: "channel", default: "s3://pixi/meso-forge"}
                    {arg: "url", default: "https://minio.isis.vanderbilt.edu"}
                ]
                cwd: "."
                cmd: [
                    "nu",
                    "meso-forge/scripts/package_publish.nu",
                    "--mode", "s3",
                    "--channel", "{{ channel }}",
                    "--url", "{{ url }}",
                    "{{ '--force' if force != '' else '' }}",
                    "{{ '--dry-run' if dry_run != '' else '' }}"
                ]
            }
        }
        {
            name: "publish-local"
            config: {
                args: [
                    {arg: "force", default: ""}
                    {arg: "channel", default: "s3://pixi-local/meso-forge"}
                    {arg: "url", default: "http://localhost:19000"}
                ]
                cmd: [
                    "nu",
                    "meso-forge/scripts/package_publish.nu",
                    "--mode", "s3",
                    "--channel", "{{ channel }}",
                    "--url", "{{ url }}",
                    "{{ '--force' if force != '' else '' }}"
                ]
            }
        }

        # Retraction tasks
        {
            name: "retract-pd"
            config: {
                args: [
                    {arg: "pkg", default: "_skeleton_python"}
                    {arg: "channel", default: "meso-forge"}
                    {arg: "versions", default: "1.0.0"}
                    {arg: "tgt_platform", default: "linux-64"}
                    {arg: "force", default: ""}
                ]
                cmd: [
                    "nu",
                    "meso-forge/scripts/package_retract.nu",
                    "{{ pkg }}",
                    "--channel={{ channel }}",
                    "--versions={{ versions }}",
                    "--method=pd",
                    "--target-platform={{ tgt_platform }}",
                    "{{ '--force' if force != '' else '' }}"
                ]
            }
        }
    ]
}

# Get meso-forge task definitions using trampoline scripts
# Alternative implementation for environments where trampoline scripts are preferred
export def get_meso_forge_trampoline_tasks [] {
    [
        # Build tasks using trampoline scripts
        {
            name: "build-all"
            config: {
                cmd: "meso-forge-build-all"
                cwd: "."
            }
        }
        {
            name: "build-noarch"
            config: {
                cmd: "meso-forge-build-noarch"
                cwd: "."
            }
        }
        {
            name: "build-platform"
            config: {
                cmd: "meso-forge-build-platform"
                cwd: "."
            }
        }
        {
            name: "build-all-platforms"
            config: {
                cmd: ["meso-forge-build-platform", "--all-platforms"]
                cwd: "."
            }
        }
        {
            name: "build-for-platform"
            config: {
                args: [
                    {arg: "platform", default: "linux-64"}
                ]
                cmd: ["meso-forge-build-platform", "--platform", "{{ platform }}"]
                cwd: "."
            }
        }
        {
            name: "build-pkg"
            config: {
                args: [
                    {arg: "pkg", default: "asciidoctor-revealjs"}
                ]
                cmd: ["meso-forge-build-single", "--recipe", "pkgs/{{ pkg }}/recipe.yaml"]
                cwd: "."
            }
        }
        {
            name: "build-dry"
            config: {
                args: [
                    {arg: "pkg", default: "asciidoctor-revealjs"}
                ]
                cmd: ["meso-forge-build-single", "--recipe", "pkgs/{{ pkg }}/recipe.yaml", "--dry-run"]
                cwd: "."
            }
        }

        # Lint tasks using trampoline scripts
        {
            name: "lint-recipes"
            config: {
                cmd: "meso-forge-lint-recipes"
                cwd: "."
            }
        }
        {
            name: "lint-recipes-fix"
            config: {
                cmd: ["meso-forge-lint-recipes", "--fix"]
                cwd: "."
            }
        }

        # Test tasks using trampoline scripts
        {
            name: "test-packages"
            config: {
                cmd: "meso-forge-test-packages"
                cwd: "."
            }
        }
        {
            name: "test-platform"
            config: {
                cmd: ["meso-forge-test-packages", "--platform"]
                cwd: "."
            }
        }
        {
            name: "test-package"
            config: {
                cmd: ["meso-forge-test-packages", "--package"]
                cwd: "."
            }
        }

        # Publishing tasks using trampoline scripts
        {
            name: "publish-pd"
            config: {
                args: [
                    {arg: "force", default: ""}
                    {arg: "channel", default: "meso-forge"}
                ]
                cwd: "."
                cmd: [
                    "meso-forge-publish",
                    "--mode", "pd",
                    "--channel", "{{ channel }}",
                    "{{ '--force' if force != '' else '' }}"
                ]
            }
        }
        {
            name: "publish-s3"
            config: {
                args: [
                    {arg: "force", default: ""}
                    {arg: "dry_run", default: ""}
                    {arg: "channel", default: "s3://pixi/meso-forge"}
                    {arg: "url", default: "https://minio.isis.vanderbilt.edu"}
                ]
                cwd: "."
                cmd: [
                    "meso-forge-publish",
                    "--mode", "s3",
                    "--channel", "{{ channel }}",
                    "--url", "{{ url }}",
                    "{{ '--force' if force != '' else '' }}",
                    "{{ '--dry-run' if dry_run != '' else '' }}"
                ]
            }
        }
        {
            name: "publish-local"
            config: {
                args: [
                    {arg: "force", default: ""}
                    {arg: "channel", default: "s3://pixi-local/meso-forge"}
                    {arg: "url", default: "http://localhost:19000"}
                ]
                cmd: [
                    "meso-forge-publish",
                    "--mode", "s3",
                    "--channel", "{{ channel }}",
                    "--url", "{{ url }}",
                    "{{ '--force' if force != '' else '' }}"
                ]
            }
        }

        # Retraction tasks using trampoline scripts
        {
            name: "retract-pd"
            config: {
                args: [
                    {arg: "pkg", default: "_skeleton_python"}
                    {arg: "channel", default: "meso-forge"}
                    {arg: "versions", default: "1.0.0"}
                    {arg: "tgt_platform", default: "linux-64"}
                    {arg: "force", default: ""}
                ]
                cmd: [
                    "meso-forge-retract",
                    "{{ pkg }}",
                    "--channel={{ channel }}",
                    "--versions={{ versions }}",
                    "--method=pd",
                    "--target-platform={{ tgt_platform }}",
                    "{{ '--force' if force != '' else '' }}"
                ]
            }
        }

        # Quality assurance tasks using trampoline scripts
        {
            name: "check-package"
            config: {
                args: [
                    {arg: "pkg", default: "_skeleton_python"}
                    {arg: "channel", default: "meso-forge"}
                ]
                cmd: [
                    "meso-forge-check-package",
                    "{{ pkg }}",
                    "--channel={{ channel }}"
                ]
            }
        }

        # Pixi task management using trampoline scripts
        {
            name: "pixi-analyze"
            config: {
                cmd: "meso-forge-pixi-analyze"
                cwd: "."
            }
        }
        {
            name: "pixi-update"
            config: {
                cmd: "meso-forge-pixi-update"
                cwd: "."
            }
        }
    ]
}

# Get the list of meso-forge task names
export def get_meso_forge_task_names [] {
    get_meso_forge_tasks | get name
}

# Check if a task name is considered a meso-forge task
export def is_meso_forge_task [task_name: string] {
    let meso_forge_task_patterns = [
        "build-all", "build-noarch", "build-platform", "build-all-platforms",
        "build-for-platform", "build-pkg", "build-dry",
        "lint-recipes", "lint-recipes-fix",
        "test-packages", "test-platform", "test-package",
        "publish-pd", "publish-s3", "publish-local",
        "retract-pd", "retract-s3", "retract-s3-local",
        "check-package", "pixi-analyze", "pixi-update"
    ]

    $task_name in $meso_forge_task_patterns or ($task_name | str contains "meso-forge")
}

# Load and validate a pixi.toml file
export def load_pixi_file [pixi_file: string] {
    # Check if pixi.toml exists
    if not ($pixi_file | path exists) {
        error make {
            msg: $"pixi.toml file not found: ($pixi_file)"
        }
    }

    # Read and parse the existing pixi.toml
    try {
        open $pixi_file
    } catch {
        error make {
            msg: $"Failed to parse TOML file: ($pixi_file)"
        }
    }
}

# Get current tasks from pixi data
export def get_current_tasks [pixi_data: record] {
    if "tasks" in $pixi_data {
        $pixi_data.tasks | transpose key value | rename name config
    } else {
        []
    }
}

# Analyze tasks to find missing, present, and outdated ones
export def analyze_task_status [current_tasks: list, expected_tasks: list] {
    let expected_task_names = $expected_tasks | get name
    let current_task_names = $current_tasks | get name

    # Find missing tasks
    let missing_tasks = $expected_task_names | where {|name|
        $name not-in $current_task_names
    }

    # Find present tasks
    let present_tasks = $expected_task_names | where {|name|
        $name in $current_task_names
    }

    # Find outdated tasks (present but different configuration)
    let outdated_tasks = $present_tasks | where {|task_name|
        let current_config = $current_tasks | where name == $task_name | get config.0
        let expected_config = $expected_tasks | where name == $task_name | get config.0
        $current_config != $expected_config
    }

    # Find non-meso-forge tasks
    let other_tasks = $current_tasks | where {|task|
        not (is_meso_forge_task $task.name)
    }

    # Find meso-forge tasks
    let meso_forge_tasks = $current_tasks | where {|task|
        is_meso_forge_task $task.name
    }

    {
        missing: $missing_tasks
        present: $present_tasks
        outdated: $outdated_tasks
        other: $other_tasks
        meso_forge: $meso_forge_tasks
        up_to_date: ($present_tasks | where {|name| $name not-in $outdated_tasks})
    }
}

# Generate a backup filename with timestamp
export def generate_backup_filename [original_file: string] {
    $"($original_file).backup.(date now | format date '%Y%m%d_%H%M%S')"
}

# Validate task configuration
export def validate_task_config [config: record] {
    # Basic validation - ensure required fields exist
    if "cmd" not-in $config {
        return false
    }

    # Check if cmd references meso-forge scripts
    let cmd_str = if ($config.cmd | describe) == "list" {
        $config.cmd | str join " "
    } else {
        $config.cmd
    }
    $cmd_str =~ "meso-forge"
}

# Create a formatted task summary for display
export def format_task_summary [analysis: record, expected_count: int] {
    let total_tasks = ($analysis.meso_forge | length) + ($analysis.other | length)

    [
        $"📊 **Task Summary**"
        $"  Total tasks in pixi.toml: ($total_tasks)"
        $"  Meso-forge tasks found: (($analysis.meso_forge | length))"
        $"  Expected meso-forge tasks: ($expected_count)"
        $"  Other tasks: (($analysis.other | length))"
        ""
    ] | str join (char newline)
}

# Format recommendations based on analysis
export def format_recommendations [analysis: record, pixi_file: string] {
    mut recommendations = ["💡 **Recommendations:**"]

    if ($analysis.missing | length) > 0 {
        $recommendations = ($recommendations | append "  - Run update command to add missing tasks")
    }

    if ($analysis.outdated | length) > 0 {
        $recommendations = ($recommendations | append "  - Run update command to refresh outdated task configurations")
    }

    if ($analysis.missing | length) == 0 and ($analysis.outdated | length) == 0 {
        $recommendations = ($recommendations | append "  - All meso-forge tasks are up to date! 🎉")
    }

    $recommendations = ($recommendations | append $"  - Use: nu meso-forge/scripts/pixi_tasks_manage.nu update --pixi-file ($pixi_file)")

    $recommendations | str join (char newline)
}

# Create updated tasks section by merging meso-forge tasks with existing tasks
export def create_updated_tasks [existing_tasks: record, meso_forge_tasks: list] {
    $meso_forge_tasks | reduce --fold $existing_tasks {|task, acc|
        $acc | upsert $task.name $task.config
    }
}

# Get tasks using the preferred implementation (direct scripts by default)
export def get_preferred_meso_forge_tasks [use_trampoline: bool = false] {
    if $use_trampoline {
        if (trampoline_scripts_available) {
            get_meso_forge_trampoline_tasks
        } else {
            print "Warning: Trampoline scripts not available, falling back to direct scripts"
            get_meso_forge_tasks
        }
    } else {
        get_meso_forge_tasks
    }
}

# Helper function to detect if trampoline scripts are available
export def trampoline_scripts_available [] {
    let commands = [
        "meso-forge-build-all"
        "meso-forge-publish"
        "meso-forge-test-packages"
        "meso-forge-lint-recipes"
    ]

    $commands | all {|cmd| (which $cmd | is-not-empty)}
}

# Analyze meso-forge tasks in pixi.toml
export def analyze_tasks [pixi_file: string, verbose: bool, show_all: bool] {
    use std log

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
export def update_tasks [pixi_file: string, dry_run: bool, verbose: bool, force: bool] {
    use std log

    if $verbose {
        log info "Starting pixi.toml update process"
    }

    # Load and validate pixi file
    let pixi_data = load_pixi_file $pixi_file

    # Get meso-forge tasks and current tasks (using direct scripts for best compatibility)
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
export def show_help [] {
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
    print ""
    print "TASK IMPLEMENTATION:"
    print "  This tool uses direct nushell script calls by default for best"
    print "  performance and compatibility. Alternative trampoline script"
    print "  implementations are available via get_meso_forge_trampoline_tasks()."
}

# Main entry point for pixi task management
export def main [
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
