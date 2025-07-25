#!/usr/bin/env nu

# Common functions and data for meso-forge pixi task management
# This module contains shared functionality used by analyze, update, and manage scripts

# Get all meso-forge task definitions with their complete configurations
export def get_meso_forge_tasks [] {
    [
        # Build tasks
        {
            name: "build-all"
            config: {
                cmd: ["nu", "meso-forge-tooling/scripts/build_all.nu"]
                cwd: "."
            }
        }
        {
            name: "build-noarch"
            config: {
                cmd: ["nu", "meso-forge-tooling/scripts/build_noarch.nu"]
                cwd: "."
            }
        }
        {
            name: "build-platform"
            config: {
                cmd: ["nu", "meso-forge-tooling/scripts/build_platform.nu"]
                cwd: "."
            }
        }
        {
            name: "build-all-platforms"
            config: {
                cmd: ["nu", "meso-forge-tooling/scripts/build_platform.nu", "--all-platforms"]
                cwd: "."
            }
        }
        {
            name: "build-for-platform"
            config: {
                args: [
                    {arg: "platform", default: "linux-64"}
                ]
                cmd: ["nu", "meso-forge-tooling/scripts/build_platform.nu", "--platform", "{{ platform }}"]
                cwd: "."
            }
        }
        {
            name: "meso-forge"
            config: {
                cmd: "nu meso-forge-tooling/scripts/meso-forge.nu"
                cwd: "."
            }
        }
        {
            name: "build-pkg"
            config: {
                args: [
                    {arg: "pkg", default: "asciidoctor-revealjs"}
                ]
                cmd: ["nu", "meso-forge-tooling/scripts/build_single.nu", "--recipe", "pkgs/{{ pkg }}/recipe.yaml"]
                cwd: "."
            }
        }
        {
            name: "build-dry"
            config: {
                args: [
                    {arg: "pkg", default: "asciidoctor-revealjs"}
                ]
                cmd: ["nu", "meso-forge-tooling/scripts/build_single.nu", "--recipe", "pkgs/{{ pkg }}/recipe.yaml", "--dry-run"]
                cwd: "."
            }
        }

        # Lint tasks
        {
            name: "lint-recipes"
            config: {
                cmd: ["nu", "meso-forge-tooling/scripts/lint_recipes.nu"]
                cwd: "."
            }
        }
        {
            name: "lint-recipes-fix"
            config: {
                cmd: ["nu", "meso-forge-tooling/scripts/lint_recipes.nu", "--fix"]
                cwd: "."
            }
        }

        # Test tasks
        {
            name: "test-packages"
            config: {
                cmd: ["nu", "meso-forge-tooling/scripts/test_packages.nu"]
                cwd: "."
            }
        }
        {
            name: "test-platform"
            config: {
                cmd: ["nu", "meso-forge-tooling/scripts/test_packages.nu", "--platform"]
                cwd: "."
            }
        }
        {
            name: "test-package"
            config: {
                cmd: ["nu", "meso-forge-tooling/scripts/test_packages.nu", "--package"]
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
                    "meso-forge-tooling/scripts/package_publish.nu",
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
                    "meso-forge-tooling/scripts/package_publish.nu",
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
                    "meso-forge-tooling/scripts/package_publish.nu",
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
                    "meso-forge-tooling/scripts/package_retract.nu",
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

# Get the list of meso-forge task names
export def get_meso_forge_task_names [] {
    get_meso_forge_tasks | get name
}

# Check if a task name is considered a meso-forge task
export def is_meso_forge_task [task_name: string] {
    let meso_forge_task_patterns = [
        "build-all", "build-noarch", "build-platform", "build-all-platforms",
        "build-for-platform", "meso-forge", "build-pkg", "build-dry",
        "lint-recipes", "lint-recipes-fix",
        "test-packages", "test-platform", "test-package",
        "publish-pd", "publish-s3", "publish-local",
        "retract-pd", "retract-s3", "retract-s3-local"
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

    # Check if cmd references meso-forge-tooling scripts
    let cmd_str = if ($config.cmd | describe) == "list" {
        $config.cmd | str join " "
    } else {
        $config.cmd
    }
    $cmd_str =~ "meso-forge-tooling"
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

    $recommendations = ($recommendations | append $"  - Use: nu meso-forge-tooling/scripts/pixi_tasks_manage.nu update --pixi-file ($pixi_file)")

    $recommendations | str join (char newline)
}

# Create updated tasks section by merging meso-forge tasks with existing tasks
export def create_updated_tasks [existing_tasks: record, meso_forge_tasks: list] {
    $meso_forge_tasks | reduce --fold $existing_tasks {|task, acc|
        $acc | upsert $task.name $task.config
    }
}
