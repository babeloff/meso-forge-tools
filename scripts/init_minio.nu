#!/usr/bin/env nu

# MinIO Client Configuration Script for meso-forge conda packages
# This script configures the MinIO client (mc) to work with MinIO servers for conda package hosting
#
# SECURITY FEATURES:
# - Prioritizes secure credential storage using system keychain/keyring
# - Tries pixi auth login first (cross-platform secure storage)
# - Uses system keychain/keyring automatically via pixi
# - Uses RATTLER_AUTH_FILE only as a last resort (less secure)
# - All credentials stored securely via pixi authentication
#
# CREDENTIAL MANAGEMENT:
# - Use --list-credentials to view stored credentials
# - Use --remove-credentials to remove stored credentials
# - Search for 'pixi' or 's3://' in your system's credential manager

# Default configuration
const DEFAULT_MINIO_URL = "http://localhost:19000"
const DEFAULT_MINIO_ACCESS_KEY = "minioadmin"
const DEFAULT_MINIO_SECRET_KEY = "minioadmin"
const DEFAULT_BUCKET_NAME = "meso-forge"
const DEFAULT_CHANNEL_NAME = "s3://meso-forge"
const DEFAULT_MINIO_ALIAS = "local-minio"

# Main command
def main [
    --url: string = $DEFAULT_MINIO_URL,           # MinIO server URL
    --access-key: string = $DEFAULT_MINIO_ACCESS_KEY,  # MinIO access key
    --secret-key: string = $DEFAULT_MINIO_SECRET_KEY,  # MinIO secret key
    --bucket: string = $DEFAULT_BUCKET_NAME,      # Bucket name
    --channel: string = $DEFAULT_CHANNEL_NAME,    # Channel name
    --alias: string = $DEFAULT_MINIO_ALIAS,       # MinIO client alias
    --list-credentials                            # List stored credentials
    --remove-credentials                          # Remove stored credentials
    --help                                        # Show help
] {
    if $help {
        show_help
        return
    }

    if $list_credentials {
        list_stored_credentials
        return
    }

    if $remove_credentials {
        remove_stored_credentials
        return
    }

    # Get configuration from environment or use parameters
    let config = {
        url: ($env.MINIO_URL? | default $url),
        access_key: ($env.MINIO_ACCESS_KEY? | default $access_key),
        secret_key: ($env.MINIO_SECRET_KEY? | default $secret_key),
        bucket: ($env.MINIO_BUCKET? | default $bucket),
        channel: ($env.MINIO_CHANNEL? | default $channel),
        alias: ($env.MINIO_ALIAS? | default $alias)
    }

    print "🚀 Initializing MinIO for meso-forge conda packages..."
    print ""

    # Check prerequisites
    if not (check_mc_available) {
        return
    }

    if not (check_minio_server $config.url) {
        print "⚠️ Continuing anyway - you may need to start MinIO server first"
        print "⚠️ Some operations may fail without a running MinIO server"
    }

    # Configure MinIO
    if not (configure_mc_alias $config) {
        return
    }

    # Create bucket and set policy
    if not (create_bucket $config) {
        return
    }

    # Update authentication using secure storage first, then fallback to RATTLER_AUTH_FILE
    if not (update_authentication $config) {
        return
    }

    # Test the setup
    if not (test_setup $config) {
        print "⚠️ Setup test failed, but configuration may still be valid"
    }

    print ""
    print "✅ MinIO initialization completed successfully!"
    print ""

    # Show configuration summary
    show_configuration $config
}

# Check if MinIO client (mc) is available
def check_mc_available [] {
    let mc_check = (^timeout 5 which mc | complete)
    if $mc_check.exit_code != 0 {
        print -e "❌ MinIO client (mc) is not installed or not in PATH"
        print "Install mc using one of these methods:"
        print "  - conda install -c conda-forge minio"
        print "  - pixi add minio"
        print "  - curl -L https://dl.min.io/client/mc/release/linux-amd64/mc -o mc && chmod +x mc"
        return false
    }

    let mc_path = ($mc_check.stdout | str trim)
    print $"ℹ️ MinIO client (mc) found: ($mc_path)"
    return true
}

# Check if MinIO server is running
def check_minio_server [url: string] {
    print $"ℹ️ Checking if MinIO server is running at ($url)..."

    let health_check = (
        ^curl --connect-timeout 5 --max-time 10 -s $"($url)/minio/health/live"
        | complete
    )

    if $health_check.exit_code == 0 {
        print $"✅ MinIO server is running at ($url)"
        return true
    } else {
        print $"⚠️ MinIO server is not accessible at ($url)"
        print "Start MinIO server manually or using docker:"
        print $"  docker run -p 19000:9000 -p 19001:9001 \\"
        print $"    -e MINIO_ROOT_USER=($env.MINIO_ACCESS_KEY? | default 'minioadmin') \\"
        print $"    -e MINIO_ROOT_PASSWORD=($env.MINIO_SECRET_KEY? | default 'minioadmin') \\"
        print $"    minio/minio server /data --console-address ':9001'"
        return false
    }
}

# Configure MinIO client alias
def configure_mc_alias [config: record] {
    print $"ℹ️ Configuring MinIO client alias '($config.alias)'..."

    # Check if alias exists and remove it
    let aliases = (^mc alias list | complete)
    if $aliases.exit_code == 0 and ($aliases.stdout | str contains $config.alias) {
        print $"ℹ️ Removing existing alias '($config.alias)'"
        ^mc alias remove $config.alias | complete | ignore
    }

    # Add new alias
    let result = (^mc alias set $config.alias $config.url $config.access_key $config.secret_key | complete)

    if $result.exit_code == 0 {
        print $"✅ MinIO client alias '($config.alias)' configured successfully"
        return true
    } else {
        print -e "❌ Failed to configure MinIO client alias"
        print -e $result.stderr
        return false
    }
}

# Create bucket if it doesn't exist
def create_bucket [config: record] {
    print $"ℹ️ Creating bucket '($config.bucket)' if it doesn't exist..."

    # Check if bucket exists
    let bucket_check = (^mc ls $"($config.alias)/($config.bucket)" | complete)

    if $bucket_check.exit_code == 0 {
        print $"ℹ️ Bucket '($config.bucket)' already exists"
    } else {
        let create_result = (^mc mb $"($config.alias)/($config.bucket)" | complete)

        if $create_result.exit_code == 0 {
            print $"✅ Bucket '($config.bucket)' created successfully"
        } else {
            print -e $"❌ Failed to create bucket '($config.bucket)'"
            print -e $create_result.stderr
            return false
        }
    }

    # Set bucket policy to allow public read access
    print $"ℹ️ Setting public read policy for bucket '($config.bucket)'..."

    let policy = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": "*",
                "Action": ["s3:GetObject"],
                "Resource": [$"arn:aws:s3:::($config.bucket)/*"]
            },
            {
                "Effect": "Allow",
                "Principal": "*",
                "Action": ["s3:ListBucket"],
                "Resource": [$"arn:aws:s3:::($config.bucket)"]
            }
        ]
    }

    let policy_file = ($nu.temp-path | path join $"minio-policy-(random chars).json")
    $policy | to json | save $policy_file

    let policy_result = (^mc policy set-json $policy_file $"($config.alias)/($config.bucket)" | complete)

    if $policy_result.exit_code == 0 {
        print $"✅ Public read policy set for bucket '($config.bucket)'"
    } else {
        print $"⚠️ Failed to set public read policy for bucket '($config.bucket)'"
        print $policy_result.stderr
    }

    rm -f $policy_file
    return true
}

# Try to store credentials in secure system keychain/keyring first
def try_secure_credential_storage [config: record] {
    print "ℹ️ Attempting to store credentials in system keychain/keyring..."

    # Extract URL without path for auth entry
    let minio_base_url = ($config.url | str replace --regex '/$' '')

    # Use pixi auth login for cross-platform secure storage
    return (try_pixi_auth_login $config $minio_base_url)
}

# Try pixi auth login (cross-platform secure storage)
def try_pixi_auth_login [config: record, url: string] {
    print "ℹ️ Attempting to use pixi auth login for secure credential storage..."

    # Check if pixi is available
    if not (which pixi | is-not-empty) {
        print "⚠️ pixi command not found, skipping secure credential storage"
        return false
    }

    # Try to login with S3 bucket format for secure storage
    let login_result = (^pixi auth login $config.channel --s3-access-key-id $config.access_key --s3-secret-access-key $config.secret_key | complete)

    if $login_result.exit_code == 0 {
        print "✅ Credentials stored securely via pixi auth login"

        # Verify storage on Linux using secret-tool (if available)
        if (which secret-tool | is-not-empty) {
            let verification = (^secret-tool search service pixi | complete)
            if $verification.exit_code == 0 and ($verification.stdout | str length) > 0 {
                print "ℹ️ Verified: Credentials stored in GNOME Keyring"
            }
        }

        return true
    } else {
        print "⚠️ pixi auth login failed:"
        if ($login_result.stderr | str length) > 0 {
            print $"   ($login_result.stderr)"
        }
        return false
    }
}

# Update authentication using secure storage first, fallback to RATTLER_AUTH_FILE
def update_authentication [config: record] {
    # First, try secure credential storage
    if (try_secure_credential_storage $config) {
        print "✅ Credentials stored securely in system keychain/keyring"
        print "ℹ️ You can view stored credentials by searching for 'pixi' or 's3://' in your system's credential manager"
        return true
    }

    print "⚠️ Secure credential storage failed, falling back to RATTLER_AUTH_FILE"
    print "⚠️ Note: RATTLER_AUTH_FILE is less secure than system keychain storage"

    return (update_rattler_auth_file $config)
}

# Fallback: Update RATTLER_AUTH_FILE with MinIO credentials (less secure)
def update_rattler_auth_file [config: record] {
    let auth_file = ($env.RATTLER_AUTH_FILE? | default ($env.HOME | path join ".rattler" "credentials.json"))

    print $"ℹ️ Updating RATTLER_AUTH_FILE at: ($auth_file)"

    # Create directory if it doesn't exist
    mkdir ($auth_file | path dirname)

    # Initialize auth file if it doesn't exist
    if not ($auth_file | path exists) {
        "{}" | save $auth_file
        print $"ℹ️ Created new auth file: ($auth_file)"
    }

    # Backup existing auth file
    let backup_file = $"($auth_file).backup.(date now | format date '%Y%m%d_%H%M%S')"
    cp $auth_file $backup_file
    print "ℹ️ Backed up existing auth file"

    # Read existing auth data
    let auth_data = (
        if ($auth_file | path exists) {
            try {
                open $auth_file | from json
            } catch {
                {}
            }
        } else {
            {}
        }
    )

    # Extract URL without path for auth entry
    let minio_base_url = ($config.url | str replace --regex '/$' '')

    # Update auth data with MinIO credentials using S3Credentials format
    let credentials = {
        S3Credentials: {
            access_key_id: $config.access_key,
            secret_access_key: $config.secret_key,
            session_token: null
        }
    }

    let updated_auth = (
        $auth_data
        | upsert $minio_base_url $credentials
        | upsert $config.channel $credentials
    )

    # Save updated auth file
    $updated_auth | to json | save $auth_file

    # Set secure permissions on auth file
    chmod 600 $auth_file
    print "ℹ️ Set secure permissions (600) on auth file"

    # Export RATTLER_AUTH_FILE if not already set
    if ($env.RATTLER_AUTH_FILE? | is-empty) {
        $env.RATTLER_AUTH_FILE = $auth_file
        print $"ℹ️ Set RATTLER_AUTH_FILE environment variable to: ($auth_file)"
        print $"⚠️ Add 'export RATTLER_AUTH_FILE=($auth_file)' to your shell profile (.bashrc, .zshrc, etc.)"
    }

    print "✅ Updated RATTLER_AUTH_FILE with MinIO credentials"
    print "⚠️ Consider using secure system keychain storage instead of RATTLER_AUTH_FILE"
    return true
}

# List stored credentials in system keychain/keyring
def list_stored_credentials [] {
    print "ℹ️ Listing stored credentials in system keychain/keyring..."
    print ""
    print "🔍 To view credentials:"
    print "  1. Use your system's credential manager GUI"
    print "  2. Search for 'pixi' or 's3://' entries"
    print ""

    # Try to check if pixi has authentication configured
    print "📋 Checking for pixi authentication..."
    print "ℹ️ Use 'pixi auth --help' to see available auth commands"
    print "ℹ️ Credentials may be stored in system keychain (search for 'rattler')"

    # Check for pixi stored credentials
    if (which pixi | is-not-empty) {
        print ""
        print "📋 Checking pixi stored credentials:"
        print "ℹ️ Credentials stored via 'pixi auth login' are in your system's secure keychain"
        print "ℹ️ Search for 'pixi' or 's3://' entries in your credential manager"

        # Verify on Linux using secret-tool
        if (which secret-tool | is-not-empty) {
            let pixi_search = (^secret-tool search service pixi | complete)
            if $pixi_search.exit_code == 0 and ($pixi_search.stdout | str length) > 0 {
                print ""
                print "📋 GNOME Keyring pixi entries:"
                print $pixi_search.stdout
            } else {
                print ""
                print "ℹ️ No pixi entries found in GNOME Keyring (may be stored in different keyring backend)"
            }
        }
    }
}

# Remove stored credentials from system keychain/keyring
def remove_stored_credentials [] {
    print "ℹ️ Removing stored credentials from system keychain/keyring..."
    print ""
    print "🗑️ To remove credentials:"
    print "  1. Use your system's credential manager GUI"
    print "  2. Find and delete entries containing 'pixi' or 's3://'"
    print ""

    # Remove pixi authentication entries
    if (which pixi | is-not-empty) {
        print ""
        print "Attempting to remove pixi authentication entries..."
        let targets = ["s3://meso-forge", "s3://rattler-credentials", "localhost", "localhost:19000", "127.0.0.1", "minio"]

        for target in $targets {
            let remove_result = (^pixi auth logout $target | complete)
            if $remove_result.exit_code == 0 {
                print $"✅ Removed pixi authentication for ($target)"
            }
        }

        # Verify removal on Linux using secret-tool
        if (which secret-tool | is-not-empty) {
            print ""
            print "Verifying removal from GNOME Keyring..."
            let verification = (^secret-tool search service pixi | complete)
            if $verification.exit_code == 0 and ($verification.stdout | str length) > 0 {
                print "⚠️ Some pixi entries may still exist in GNOME Keyring"
            } else {
                print "✅ Verified: No pixi entries found in GNOME Keyring"
            }
        }
    } else {
        print "⚠️ pixi command not found, cannot remove secure credentials"
    }

    print ""
    print "⚠️ You may also want to remove or backup your RATTLER_AUTH_FILE if it exists:"
    let auth_file = ($env.RATTLER_AUTH_FILE? | default ($env.HOME | path join ".rattler" "credentials.json"))
    if ($auth_file | path exists) {
        print $"  File location: ($auth_file)"
        print $"  To backup: cp ($auth_file) ($auth_file).backup"
        print $"  To remove: rm ($auth_file)"
    } else {
        print "  No RATTLER_AUTH_FILE found"
    }
}

# Test the setup by creating a test file and listing bucket contents
def test_setup [config: record] {
    print "ℹ️ Testing MinIO setup..."

    let test_file = ($nu.temp-path | path join $"minio-test-(random chars).txt")
    $"MinIO conda channel test file - (date now)" | save $test_file

    # Upload test file
    let upload_result = (^mc cp $test_file $"($config.alias)/($config.bucket)/test.txt" | complete)

    if $upload_result.exit_code == 0 {
        print "✅ Successfully uploaded test file"

        # List bucket contents
        print "ℹ️ Bucket contents:"
        ^mc ls $"($config.alias)/($config.bucket)/"

        # Remove test file
        ^mc rm $"($config.alias)/($config.bucket)/test.txt" | ignore
        print "ℹ️ Cleaned up test file"
    } else {
        print -e "❌ Failed to upload test file"
        print -e $upload_result.stderr
        rm -f $test_file
        return false
    }

    rm -f $test_file
    return true
}

# Display configuration summary
def show_configuration [config: record] {
    print "ℹ️ MinIO Configuration Summary:"
    print $"  MinIO URL: ($config.url)"
    print $"  Bucket Name: ($config.bucket)"
    print $"  Channel Name: ($config.channel)"
    print $"  MC Alias: ($config.alias)"
    let auth_method = if ($env.RATTLER_AUTH_FILE? | is-not-empty) {
        $"RATTLER_AUTH_FILE: ($env.RATTLER_AUTH_FILE)"
    } else {
        "System keychain/keyring (secure)"
    }
    print $"  Auth Method: ($auth_method)"
    print ""
    print "ℹ️ Usage examples:"
    print "  # Build and publish packages to local MinIO"
    print "  pixi run build-all"
    print "  pixi run publish-local"
    print ""
    print "  # Index the conda channel"
    print "  pixi run index-local"
    print ""
    print "  # Add channel to your conda/mamba configuration"
    print $"  conda config --add channels ($config.url)/($config.bucket)"
    print ""
    print "  # Use with pixi.toml"
    print $"  channels = [\"($config.url)/($config.bucket)\", \"conda-forge\"]"
}

# Show help information
def show_help [] {
    print "🛠️  MinIO Initialization Script for meso-forge conda packages"
    print ""
    print "USAGE:"
    print "    nu init_minio.nu [OPTIONS]"
    print ""
    print "OPTIONS:"
    print "    --url URL               MinIO server URL (default: http://localhost:19000)"
    print "    --access-key KEY        MinIO access key (default: minioadmin)"
    print "    --secret-key KEY        MinIO secret key (default: minioadmin)"
    print "    --bucket NAME           Bucket name (default: meso-forge)"
    print "    --channel NAME          Channel name (default: s3://meso-forge)"
    print "    --alias NAME            MinIO client alias (default: local-minio)"
    print "    --list-credentials      List stored credentials in system keychain"
    print "    --remove-credentials    Remove stored credentials from system keychain"
    print "    --help                  Show this help message"
    print ""
    print "ENVIRONMENT VARIABLES:"
    print "    MINIO_URL           MinIO server URL"
    print "    MINIO_ACCESS_KEY    MinIO access key"
    print "    MINIO_SECRET_KEY    MinIO secret key"
    print "    MINIO_BUCKET        Bucket name"
    print "    MINIO_CHANNEL       Channel name"
    print "    MINIO_ALIAS         MinIO client alias"
    print "    RATTLER_AUTH_FILE   Path to rattler auth file (fallback, less secure)"
    print ""
    print "EXAMPLES:"
    print "    # Use defaults (localhost:19000, minioadmin/minioadmin)"
    print "    nu init_minio.nu"
    print ""
    print "    # Custom MinIO server"
    print "    nu init_minio.nu --url https://minio.example.com:9000 --access-key mykey --secret-key mysecret"
    print ""
    print "    # Using environment variables"
    print "    $env.MINIO_URL = 'https://minio.example.com:9000'"
    print "    $env.MINIO_ACCESS_KEY = 'mykey'"
    print "    $env.MINIO_SECRET_KEY = 'mysecret'"
    print "    nu init_minio.nu"
    print ""
    print "    # List stored credentials"
    print "    nu init_minio.nu --list-credentials"
    print ""
    print "    # Remove stored credentials"
    print "    nu init_minio.nu --remove-credentials"
    print ""
    print "PREREQUISITES:"
    print "    - MinIO client (mc) must be installed"
    print "    - MinIO server must be running and accessible"
    print ""
    print "🔐 SECURITY NOTES:"
    print "    - This script uses SECURE credential storage via pixi auth login"
    print "    - Uses `pixi auth login s3://bucket` for cross-platform keyring storage"
    print "    - Automatically integrates with system credential managers"
    print "    - RATTLER_AUTH_FILE is used only when pixi is unavailable (less secure)"
    print "    - Linux verification: Use 'secret-tool search service pixi' to verify storage"
    print "    - Credentials are stored with 'pixi' service name in S3 format"
    print ""
    print "CREDENTIAL MANAGEMENT:"
    print "    # List stored credentials"
    print "    nu init_minio.nu --list-credentials"
    print ""
    print "    # Remove stored credentials"
    print "    nu init_minio.nu --remove-credentials"
    print ""
    print "    # Manual credential management"
    print "    pixi auth logout s3://meso-forge  # Remove S3 credentials"
    print "    secret-tool search service pixi   # Verify on Linux (GNOME Keyring)"
    print ""
    print "NOTE:"
    print "    This script only configures the MinIO client. It does not start or manage"
    print "    the MinIO server itself. Ensure your MinIO server is running before"
    print "    running this configuration script."
    print ""
    print "For more information, see: https://github.com/phreed/meso-forge-tools"
}
