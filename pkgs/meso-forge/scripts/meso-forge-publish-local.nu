#!/usr/bin/env nu

def main [...script_args: string] {
  # Set local MinIO configuration
  let local_args = [
    "--mode", "s3",
    "--channel", "s3://pixi-local/meso-forge",
    "--url", "http://localhost:19000"
  ]

  # Process arguments to convert key=value format from pixi to actual flags
  let processed_args = ($script_args | each { |arg|
    if $arg == "--force" or $arg == "force=--force" {
      "--force"
    } else if $arg == "--dry-run" or $arg == "dryrun=--dry-run" {
      "--dry-run"
    } else if $arg == "--verbose" or $arg == "verbose=--verbose" {
      "--verbose"
    } else if $arg != "" {
      # For any other non-empty argument, pass it through
      $arg
    } else {
      null
    }
  } | where $it != null)

  let all_args = ($local_args | append $processed_args)

  # Execute the publish script with local MinIO settings
  exec nu ($env.CONDA_PREFIX)/share/meso-forge-tooling/scripts/package_publish.nu ...$all_args
}
