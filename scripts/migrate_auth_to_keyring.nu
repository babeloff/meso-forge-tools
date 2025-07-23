#!/usr/bin/env nu

# RATTLER_AUTH_FILE to Keyring Migration Script
# This script reads a RATTLER_AUTH_FILE and migrates all credentials to platform keyring storage
#
# SECURITY MODEL:
# - Reads existing RATTLER_AUTH_FILE or specified auth file
# - Converts each credential entry to equivalent 'pixi auth login' commands
# - Supports all authentication types: BearerToken, CondaToken, BasicHttp, S3Credentials
# - Provides dry-run mode to preview commands before execution
# - Validates credentials before migration
# - Optionally backs up and removes original file after successful migration
#
# Usage:
#   nu migrate_auth_to_keyring.nu
#   nu migrate_auth_to_keyring.nu --auth-file ~/.rattler/credentials.json
#   nu migrate_auth_to_keyring.nu --dry-run
#   nu migrate_auth_to_keyring.nu --remove-after-migration

def main [
    --auth-file: string = ""             # Path to RATTLER_AUTH_FILE (default: from env or ~/.rattler/credentials.json)
    --dry-run                           # Show pixi auth login commands without executing
    --remove-after-migration            # Remove auth file after successful migration
    --verbose                           # Show detailed output
    --help                              # Show help
] {
    if $help {
        show_help
        return
    }

    print "🔄 RATTLER_AUTH_FILE to Keyring Migration"
    print "═══════════════════════════════════════"
    print ""

    # Determine auth file path
    let auth_file_path = get_auth_file_path $auth_file

    if ($auth_file_path | is-empty) {
        print "❌ No auth file found"
        print "   Set RATTLER_AUTH_FILE environment variable or use --auth-file parameter"
        return
    }

    print $"📄 Auth file: ($auth_file_path)"
    print $"📋 Mode: (if $dry_run { 'DRY RUN' } else { 'EXECUTE' })"
    print ""

    # Check prerequisites
    if not (check_prerequisites) {
        return
    }

    # Read and parse auth file
    let auth_data = read_auth_file $auth_file_path
    if ($auth_data | is-empty) {
        return
    }

    # Convert to pixi auth login commands
    let login_commands = convert_to_login_commands $auth_data $verbose

    if ($login_commands | is-empty) {
        print "ℹ️ No valid credentials found to migrate"
        return
    }

    print $"🔍 Found (($login_commands | length)) credential\(s\) to migrate:"
    print ""

    # Execute or preview commands
    let migration_results = execute_migrations $login_commands $dry_run $verbose

    # Summary
    show_migration_summary $migration_results $dry_run

    # Handle post-migration cleanup
    if not $dry_run and $remove_after_migration {
        handle_file_cleanup $auth_file_path $migration_results
    }
}

# Determine the auth file path to use
def get_auth_file_path [provided_path: string] {
    if ($provided_path | is-not-empty) and $provided_path != "" {
        return $provided_path
    }

    # Check RATTLER_AUTH_FILE environment variable
    let env_path = ($env.RATTLER_AUTH_FILE? | default "")
    if not ($env_path | is-empty) {
        return $env_path
    }

    # Check default location
    let default_path = ($env.HOME | path join ".rattler" "credentials.json")
    if ($default_path | path exists) {
        return $default_path
    }

    return ""
}

# Check if required tools are available
def check_prerequisites [] {
    print "🔍 Checking prerequisites..."

    # Check if pixi is available
    if not (which pixi | is-not-empty) {
        print "❌ pixi not found"
        print "   Please install pixi first"
        return false
    }

    print "✅ Prerequisites satisfied"
    return true
}

# Read and parse the auth file
def read_auth_file [file_path: string] {
    if not ($file_path | path exists) {
        print $"❌ Auth file not found: ($file_path)"
        return {}
    }

    print $"📖 Reading auth file: ($file_path)"

    try {
        let auth_data = (open $file_path)
        if ($auth_data | describe) =~ "record" {
            print $"✅ Successfully parsed auth file with ($auth_data | columns | length) entries"
            return $auth_data
        } else {
            print $"❌ Auth file is not a valid JSON object: ($auth_data | describe)"
            return {}
        }
    } catch { |err|
        print $"❌ Failed to parse auth file: ($err.msg)"
        return {}
    }
}

# Convert auth data to pixi auth login commands
def convert_to_login_commands [auth_data: record, verbose: bool] {
    mut commands = []

    for entry in ($auth_data | transpose host credentials) {
        let host = $entry.host
        let creds = $entry.credentials

        # Skip comment entries
        if ($host | str starts-with "_") {
            if $verbose {
                print $"⏭️ Skipping comment entry: ($host)"
            }
            continue
        }

        let command = build_login_command $host $creds $verbose

        if not ($command | is-empty) {
            $commands = ($commands | append $command)
        } else if $verbose {
            print $"⚠️ Skipped ($host) - no valid credentials found"
        }
    }

    return $commands
}

# Build a pixi auth login command for a specific host and credentials
def build_login_command [host: string, credentials: any, verbose: bool] {
    if $verbose {
        print $"🔧 Processing credentials for: ($host)"
    }

    # Handle different credential types
    if ($credentials | describe | str contains "record") {
        return (build_record_command $host $credentials $verbose)
    } else {
        if $verbose {
            print $"⚠️ Unsupported credential format for ($host): ($credentials | describe)"
        }
        return {}
    }
}

# Build command for record-type credentials
def build_record_command [host: string, credentials: record, verbose: bool] {
    # Check for BearerToken (prefix.dev)
    if "BearerToken" in $credentials {
        let token = $credentials.BearerToken
        if $verbose {
            print $"  🔑 Found BearerToken for ($host)"
        }
        return {
            host: $host,
            type: "BearerToken",
            command: ["pixi", "auth", "login", $host, "--token", $token],
            description: $"Bearer token authentication for ($host)"
        }
    }

    # Check for CondaToken (anaconda.org, quetz)
    if "CondaToken" in $credentials {
        let token = $credentials.CondaToken
        if $verbose {
            print $"  🔑 Found CondaToken for ($host)"
        }
        return {
            host: $host,
            type: "CondaToken",
            command: ["pixi", "auth", "login", $host, "--conda-token", $token],
            description: $"Conda token authentication for ($host)"
        }
    }

    # Check for BasicHttp (artifactory, custom servers)
    if "BasicHttp" in $credentials {
        let basic_creds = $credentials.BasicHttp
        if "username" in $basic_creds and "password" in $basic_creds {
            let username = $basic_creds.username
            let password = $basic_creds.password
            if $verbose {
                print $"  🔑 Found BasicHttp credentials for ($host)"
            }
            return {
                host: $host,
                type: "BasicHttp",
                command: ["pixi", "auth", "login", $host, "--username", $username, "--password", $password],
                description: $"Basic HTTP authentication for ($host)"
            }
        }
    }

    # Check for S3Credentials (S3-compatible storage)
    if "S3Credentials" in $credentials {
        let s3_creds = $credentials.S3Credentials
        if "access_key_id" in $s3_creds and "secret_access_key" in $s3_creds {
            let access_key = $s3_creds.access_key_id
            let secret_key = $s3_creds.secret_access_key
            let session_token = ($s3_creds.session_token? | default null)

            if $verbose {
                print $"  🔑 Found S3Credentials for ($host)"
            }

            mut cmd = ["pixi", "auth", "login", $host, "--s3-access-key-id", $access_key, "--s3-secret-access-key", $secret_key]

            if ($session_token | is-not-empty) and $session_token != null {
                $cmd = ($cmd | append ["--s3-session-token", $session_token])
            }

            return {
                host: $host,
                type: "S3Credentials",
                command: $cmd,
                description: $"S3 credentials for ($host)"
            }
        }
    }

    if $verbose {
        print $"  ⚠️ Unknown credential type for ($host): ($credentials | columns | str join ', ')"
    }
    return {}
}

# Execute or preview the migration commands
def execute_migrations [commands: list, dry_run: bool, verbose: bool] {
    let results = ($commands | each { |cmd_info|
        let host = $cmd_info.host
        let cmd_type = $cmd_info.type
        let command = $cmd_info.command
        let description = $cmd_info.description

        print $"🔐 ($description)"

        if $dry_run {
            print $"[DRY RUN] Would run: ($command | str join ' ') \(with RATTLER_AUTH_FILE unset\)"
            print ""
            {
                host: $host,
                type: $cmd_type,
                success: true,
                message: "Dry run - not executed"
            }
        } else {
            try {
                # Unset RATTLER_AUTH_FILE to ensure pixi operates on keyring directly
                let result = (
                    with-env {RATTLER_AUTH_FILE: null} {
                        ^($command.0) ...$command.1 | complete
                    }
                )
                if $result.exit_code == 0 {
                    print $"✅ Successfully migrated credentials for ($host)"
                    if $verbose {
                        print $"   Command: ($command | str join ' ')"
                    }
                    print ""
                    {
                        host: $host,
                        type: $cmd_type,
                        success: true,
                        message: "Migration successful"
                    }
                } else {
                    print $"❌ Failed to migrate credentials for ($host)"
                    print $"   Error: ($result.stderr)"
                    if $verbose {
                        print $"   Command: ($command | str join ' ')"
                    }
                    print ""
                    {
                        host: $host,
                        type: $cmd_type,
                        success: false,
                        message: $result.stderr
                    }
                }
            } catch { |err|
                print $"❌ Failed to execute command for ($host)"
                print $"   Error: ($err.msg)"
                if $verbose {
                    print $"   Command: ($command | str join ' ')"
                }
                print ""
                {
                    host: $host,
                    type: $cmd_type,
                    success: false,
                    message: $err.msg
                }
            }
        }
    })

    return $results
}

# Show migration summary
def show_migration_summary [results: list, dry_run: bool] {
    let successful = ($results | where success == true | length)
    let failed = ($results | where success == false | length)
    let total = ($results | length)

    print "📊 Migration Summary"
    print "══════════════════"

    if $dry_run {
        print $"📋 Commands previewed: ($total)"
        print "ℹ️ Use without --dry-run to execute migration"
    } else {
        print $"✅ Successful migrations: ($successful)"
        if $failed > 0 {
            print $"❌ Failed migrations: ($failed)"
            print ""
            print "Failed migrations:"
            $results | where success == false | each { |result|
                print $"  • ($result.host) (($result.type)): ($result.message)"
            }
        }
        print $"📊 Total processed: ($total)"

        if $successful > 0 {
            print ""
            print "🎉 Credentials have been migrated to platform keyring!"
            print "💡 You can now verify with: pixi auth logout <host> (shows if credentials exist)"
        }
    }
    print ""
}

# Handle post-migration file cleanup
def handle_file_cleanup [auth_file_path: string, results: list] {
    let successful_migrations = ($results | where success == true | length)
    let total_migrations = ($results | length)

    if $successful_migrations == $total_migrations and $total_migrations > 0 {
        print "🗑️ All migrations successful, removing auth file..."

        # Create backup first
        let timestamp = (date now | format date '%Y%m%d_%H%M%S')
        let backup_path = $"($auth_file_path).backup.($timestamp)"

        try {
            cp $auth_file_path $backup_path
            print $"📄 Created backup: ($backup_path)"

            rm $auth_file_path
            print $"✅ Removed original auth file: ($auth_file_path)"
            print "⚠️ RATTLER_AUTH_FILE environment variable should be unset if it points to this file"
        } catch { |err|
            print $"❌ Failed to remove auth file: ($err.msg)"
            print $"   Manual removal required: ($auth_file_path)"
        }
    } else {
        print "⚠️ Some migrations failed, keeping original auth file"
        print $"   Auth file location: ($auth_file_path)"
    }
}

# Show help information
def show_help [] {
    print "RATTLER_AUTH_FILE to Keyring Migration Script"
    print "════════════════════════════════════════════"
    print ""
    print "This script migrates credentials from RATTLER_AUTH_FILE to platform keyring storage"
    print "using 'pixi auth login' commands. This is recommended for better security."
    print ""
    print "USAGE:"
    print "    nu migrate_auth_to_keyring.nu [OPTIONS]"
    print ""
    print "OPTIONS:"
    print "    --auth-file PATH            Path to auth file (default: RATTLER_AUTH_FILE env or ~/.rattler/credentials.json)"
    print "    --dry-run                   Preview commands without executing"
    print "    --remove-after-migration    Remove auth file after successful migration"
    print "    --verbose                   Show detailed output"
    print "    --help                      Show this help message"
    print ""
    print "EXAMPLES:"
    print "    # Migrate from default location (dry run first)"
    print "    nu migrate_auth_to_keyring.nu --dry-run"
    print "    nu migrate_auth_to_keyring.nu"
    print ""
    print "    # Migrate from specific file"
    print "    nu migrate_auth_to_keyring.nu --auth-file /path/to/credentials.json"
    print ""
    print "    # Migrate and remove original file"
    print "    nu migrate_auth_to_keyring.nu --remove-after-migration"
    print ""
    print "SUPPORTED CREDENTIAL TYPES:"
    print "    • BearerToken     - prefix.dev (--token)"
    print "    • CondaToken      - anaconda.org, quetz (--conda-token)"
    print "    • BasicHttp       - artifactory, custom servers (--username, --password)"
    print "    • S3Credentials   - S3-compatible storage (--s3-access-key-id, --s3-secret-access-key)"
    print ""
    print "CREDENTIAL PRIORITY AFTER MIGRATION:"
    print "    1. RATTLER_AUTH_FILE (if still present) - highest priority"
    print "    2. --auth-file command line parameter"
    print "    3. Platform keyring (newly migrated credentials)"
    print "    4. ~/.rattler/credentials.json (legacy fallback)"
    print ""
    print "SECURITY NOTES:"
    print "    • Migrated credentials are stored securely in platform keyring"
    print "    • Original auth file is backed up before removal (if --remove-after-migration is used)"
    print "    • Use --dry-run to preview all commands before execution"
    print "    • RATTLER_AUTH_FILE is automatically unset during pixi auth commands"
    print "    • After migration, consider unsetting RATTLER_AUTH_FILE environment variable"
    print ""
    print "VERIFICATION:"
    print "    # Check if credentials were migrated successfully"
    print "    pixi auth logout <host>  # Shows if credentials exist without removing them"
    print ""
    print "    # Test authentication"
    print "    pixi search some-package -c <channel>  # Will use keyring credentials"
}
