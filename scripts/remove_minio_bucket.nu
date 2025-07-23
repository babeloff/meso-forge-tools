#!/usr/bin/env nu

# MinIO Bucket Removal Script for meso-forge conda packages
# This script removes a MinIO bucket and cleans up associated credentials
#
# SECURITY MODEL:
# - Removes bucket and all its contents (with confirmation)
# - Cleans up mc alias configuration
# - Removes credentials from platform keyring via 'pixi auth logout'
# - Removes credentials from ~/.rattler/credentials.json if present
# - Provides dry-run mode to preview actions
#
# Usage:
#   nu remove_minio_bucket.nu --server http://localhost:19000 --bucket meso-forge
#   nu remove_minio_bucket.nu --server http://localhost:19000 --bucket meso-forge --dry-run
#   nu remove_minio_bucket.nu --server http://localhost:19000 --bucket meso-forge --force

# Default configuration
const DEFAULT_MINIO_URL = "http://localhost:19000"
const DEFAULT_BUCKET_NAME = "meso-forge"
const DEFAULT_MINIO_ALIAS = "local-minio"

def main [
    --server: string = $DEFAULT_MINIO_URL,      # MinIO server URL
    --bucket: string = $DEFAULT_BUCKET_NAME,    # Bucket name to remove
    --alias: string = $DEFAULT_MINIO_ALIAS,     # MinIO client alias (for bucket operations only)
    --dry-run                                   # Show what would be done without executing
    --force                                     # Skip confirmation prompts
    --help                                      # Show help
] {
    if $help {
        show_help
        return
    }

    print "🗑️ MinIO Bucket Removal Tool"
    print "═══════════════════════════"
    print ""

    let config = {
        server: $server,
        bucket: $bucket,
        alias: $alias,
        channel: $"s3://($bucket)",
        dry_run: $dry_run,
        force: $force
    }

    # Show configuration
    print $"📍 Server: ($config.server)"
    print $"📦 Bucket: ($config.bucket)"
    print $"🏷️ Alias: ($config.alias)"
    print $"📋 Mode: (if $config.dry_run { 'DRY RUN' } else { 'EXECUTE' })"
    print ""

    # Step 1: Check prerequisites
    if not (check_prerequisites $config) {
        return
    }

    # Step 2: Check bucket exists and show contents
    if not (check_bucket_status $config) {
        return
    }

    # Step 3: Get confirmation (unless --force or --dry-run)
    if not $config.dry_run and not $config.force {
        if not (get_user_confirmation $config) {
            print "❌ Operation cancelled by user"
            return
        }
    }

    # Step 4: Remove bucket contents and bucket
    if not (remove_bucket $config) {
        return
    }

    # Step 5: Remove keyring credentials
    remove_keyring_credentials $config

    # Step 6: Remove RATTLER_AUTH_FILE entries
    remove_auth_file_entries $config

    if $config.dry_run {
        print "🔍 DRY RUN COMPLETED - No actual changes were made"
    } else {
        print "✅ Bucket removal completed successfully!"
    }
}

# Check prerequisites
def check_prerequisites [config: record] {
    print "🔍 Checking prerequisites..."

    # Check if mc (MinIO client) is available
    if not (which mc | is-not-empty) {
        print "❌ MinIO client (mc) not found"
        print "   Install it with: pixi add minio"
        return false
    }

    # Check if pixi is available
    if not (which pixi | is-not-empty) {
        print "❌ pixi not found"
        print "   pixi is required for keyring credential management"
        return false
    }

    print "✅ Prerequisites satisfied"
    return true
}

# Check bucket status and show contents
def check_bucket_status [config: record] {
    print "📦 Checking bucket status..."

    # Check if alias exists
    let aliases = (try { ^mc alias list | lines | where ($it | str contains $config.alias) } catch { [] })
    if ($aliases | is-empty) {
        print $"⚠️ MinIO alias '($config.alias)' not found"
        print "   This may indicate the bucket was already removed or never configured"
        return true
    }

    # Check if bucket exists
    let bucket_check = (try { ^mc ls $"($config.alias)/($config.bucket)" | complete } catch { {exit_code: 1, stdout: "", stderr: ""} })
    if $bucket_check.exit_code != 0 {
        print $"⚠️ Bucket '($config.bucket)' not found on server"
        print "   Proceeding with credential cleanup only"
        return true
    }

    # Show bucket contents
    print $"📂 Bucket '($config.bucket)' contents:"
    let contents = (try { ^mc ls --recursive $"($config.alias)/($config.bucket)" | lines } catch { [] })
    if ($contents | is-empty) {
        print "   (empty bucket)"
    } else {
        print $"   Found ($contents | length) objects:"
        $contents | first 10 | each { |item| print $"   - ($item)" }
        if ($contents | length) > 10 {
            print $"   ... and (($contents | length) - 10) more objects"
        }
    }
    print ""

    return true
}

# Get user confirmation
def get_user_confirmation [config: record] {
    print "⚠️ WARNING: This operation will:"
    print $"   • Remove bucket '($config.bucket)' and ALL its contents"
    print $"   • Remove credentials from platform keyring"
    print "   • Remove credentials from RATTLER_AUTH_FILE (if present)"
    print $"   • mc alias '($config.alias)' will NOT be removed (may be used for other buckets)"
    print ""
    print "This action CANNOT be undone!"
    print ""

    let response = (input "Do you want to continue? (yes/no): ")
    return (($response | str downcase | str trim) == "yes")
}

# Remove bucket and its contents
def remove_bucket [config: record] {
    print "🗑️ Removing bucket..."

    if $config.dry_run {
        print $"[DRY RUN] Would remove bucket: ($config.alias)/($config.bucket)"
        return true
    }

    # Remove bucket and all contents recursively
    let result = (try { ^mc rb --force $"($config.alias)/($config.bucket)" | complete } catch { {exit_code: 1, stdout: "", stderr: "Bucket not found"} })

    if $result.exit_code == 0 {
        print $"✅ Bucket '($config.bucket)' removed successfully"
        return true
    } else if ($result.stderr | str contains "not found") or ($result.stderr | str contains "NoSuchBucket") {
        print $"⚠️ Bucket '($config.bucket)' was already removed or doesn't exist"
        return true
    } else {
        print $"❌ Failed to remove bucket '($config.bucket)'"
        print $"   Error: ($result.stderr)"
        return false
    }
}



# Remove credentials from platform keyring
def remove_keyring_credentials [config: record] {
    print "🔐 Removing keyring credentials..."

    let auth_targets = [
        $config.channel,                    # s3://bucket-name
        $config.server,                     # http://localhost:19000
        $"($config.server)/($config.bucket)" # http://localhost:19000/bucket-name
    ]

    for $target in $auth_targets {
        if $config.dry_run {
            print $"[DRY RUN] Would run: pixi auth logout ($target) \(with RATTLER_AUTH_FILE unset\)"
        } else {
            # Unset RATTLER_AUTH_FILE to ensure pixi operates on keyring directly
            let result = (try {
                with-env {RATTLER_AUTH_FILE: null} {
                    ^pixi auth logout $target | complete
                }
            } catch { {exit_code: 1, stdout: "", stderr: ""} })
            if $result.exit_code == 0 {
                print $"✅ Removed keyring credentials for: ($target)"
            } else {
                print $"ℹ️ No keyring credentials found for: ($target)"
            }
        }
    }
}

# Remove entries from RATTLER_AUTH_FILE
def remove_auth_file_entries [config: record] {
    print "📄 Checking RATTLER_AUTH_FILE..."

    let auth_file = ($env.RATTLER_AUTH_FILE? | default ($env.HOME | path join ".rattler" "credentials.json"))

    if not ($auth_file | path exists) {
        print $"ℹ️ Auth file not found: ($auth_file)"
        return
    }

    if $config.dry_run {
        print $"[DRY RUN] Would remove entries from: ($auth_file)"
        return
    }

    # Read and update auth file
    let auth_data = (try { open $auth_file | from json } catch { {} })

    let keys_to_remove = [
        $config.server,
        $config.channel,
        $"($config.server)/($config.bucket)"
    ]

    mut updated_auth = $auth_data
    mut removed_count = 0

    for $key in $keys_to_remove {
        if ($key in $updated_auth) {
            $updated_auth = ($updated_auth | reject $key)
            $removed_count = ($removed_count + 1)
            print $"✅ Removed auth entry: ($key)"
        }
    }

    if $removed_count > 0 {
        # Backup original file
        let backup_file = $"($auth_file).backup.(date now | format date '%Y%m%d_%H%M%S')"
        cp $auth_file $backup_file
        print $"📄 Backed up original auth file to: ($backup_file)"

        # Save updated auth file
        $updated_auth | to json | save --force $auth_file
        print $"✅ Updated auth file: ($auth_file)"
    } else {
        print $"ℹ️ No matching entries found in auth file"
    }
}

# Show help information
def show_help [] {
    print "MinIO Bucket Removal Script"
    print "═════════════════════════"
    print ""
    print "USAGE:"
    print "    nu remove_minio_bucket.nu [OPTIONS]"
    print ""
    print "OPTIONS:"
    print "    --server URL            MinIO server URL (default: http://localhost:19000)"
    print "    --bucket NAME           Bucket name to remove (default: meso-forge)"
    print "    --alias NAME            MinIO client alias for bucket operations (default: local-minio)"
    print "    --dry-run               Show what would be done without executing"
    print "    --force                 Skip confirmation prompts"
    print "    --help                  Show this help message"
    print ""
    print "EXAMPLES:"
    print "    # Remove local meso-forge bucket (with confirmation)"
    print "    nu remove_minio_bucket.nu"
    print ""
    print "    # Remove specific bucket from remote server"
    print "    nu remove_minio_bucket.nu --server https://minio.example.com --bucket my-bucket"
    print ""
    print "    # Preview what would be removed (dry run)"
    print "    nu remove_minio_bucket.nu --dry-run"
    print ""
    print "    # Remove without confirmation prompts"
    print "    nu remove_minio_bucket.nu --force"
    print ""
    print "WHAT IS REMOVED:"
    print "    • Bucket and all its contents"
    print "    • Platform keyring credentials (via 'pixi auth logout')"
    print "    • RATTLER_AUTH_FILE entries (if present)"
    print ""
    print "WHAT IS PRESERVED:"
    print "    • mc alias configuration (may be used for other buckets)"
    print ""
    print "SECURITY NOTES:"
    print "    • This script removes bucket contents permanently"
    print "    • Credentials are removed from platform keyring via 'pixi auth logout'"
    print "    • RATTLER_AUTH_FILE is automatically unset during pixi auth operations"
    print "    • RATTLER_AUTH_FILE entries are cleaned up automatically"
    print "    • mc alias configuration is preserved (may be used for other buckets)"
    print "    • Use --dry-run to preview actions before execution"
    print "    • Original auth files are backed up before modification"
}
