#!/usr/bin/env nu

# Simple credential storage test for MinIO authentication
# This script tests only the credential storage functionality without MinIO server dependencies

# Default configuration
const DEFAULT_MINIO_URL = "http://localhost:19000"
const DEFAULT_MINIO_ACCESS_KEY = "minioadmin"
const DEFAULT_MINIO_SECRET_KEY = "minioadmin"

# Main command
def main [
    --url: string = $DEFAULT_MINIO_URL,           # MinIO server URL
    --access-key: string = $DEFAULT_MINIO_ACCESS_KEY,  # MinIO access key
    --secret-key: string = $DEFAULT_MINIO_SECRET_KEY,  # MinIO secret key
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
        secret_key: ($env.MINIO_SECRET_KEY? | default $secret_key)
    }

    print "🔐 Testing MinIO credential storage..."
    print ""

    # Test secure credential storage
    if (test_secure_credential_storage $config) {
        print "✅ Credential storage test successful!"
        print ""
        print "🔍 Now check your credentials:"
        print "  - In Seahorse: Search for 'pixi' or 's3://'"
        print "  - Command line: secret-tool search service pixi"
    } else {
        print "❌ Credential storage test failed"
    }
}

# Test secure credential storage methods
def test_secure_credential_storage [config: record] {
    print "ℹ️ Testing secure credential storage via pixi auth login..."

    # Extract URL without path for auth entry
    let minio_base_url = ($config.url | str replace --regex '/$' '')

    # Use pixi auth login for cross-platform secure storage
    return (try_pixi_auth_login $config $minio_base_url)
}

# Try pixi auth login (cross-platform secure storage)
def try_pixi_auth_login [config: record, url: string] {
    print "ℹ️ Testing pixi auth login for secure credential storage..."

    # Check if pixi is available
    if not (which pixi | is-not-empty) {
        print "⚠️ pixi command not found, skipping secure credential storage"
        return false
    }

    # Try to login with S3 bucket format for secure storage
    let bucket_name = "s3://meso-forge"  # Use S3 bucket format for keyring storage
    let login_result = (^pixi auth login $bucket_name --s3-access-key-id $config.access_key --s3-secret-access-key $config.secret_key | complete)

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

# List stored credentials in system keychain/keyring
def list_stored_credentials [] {
    print "ℹ️ Listing stored credentials in system keychain/keyring..."
    print ""

    print "🔍 To view credentials:"
    print "  1. Use your system's credential manager GUI"
    print "  2. Search for 'pixi' or 's3://' entries"
    print ""

    if (which pixi | is-not-empty) {
        print "📋 Credentials stored via pixi auth in system keychain (search for 'pixi' or 's3://' entries)"

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

    # Try to remove legacy rattler entries on Linux using secret-tool
    if (which secret-tool | is-not-empty) {
        print "Attempting to remove legacy rattler entries..."
        let search_result = (^secret-tool search service rattler | complete)
        if $search_result.exit_code == 0 and ($search_result.stdout | str length) > 0 {
            # Parse the output to find usernames and remove them
            let output_lines = ($search_result.stdout | lines)
            let username_lines = ($output_lines | where {|line| $line | str starts-with "attribute.username = "})

            if ($username_lines | length) > 0 {
                for entry in $username_lines {
                    let username = ($entry | str replace "attribute.username = " "")
                    let remove_result = (^secret-tool clear service rattler username $username | complete)
                    if $remove_result.exit_code == 0 {
                        print $"✅ Removed rattler entry for ($username)"
                    } else {
                        print $"⚠️ Failed to remove rattler entry for ($username)"
                    }
                }
            } else {
                # Try removing with a generic approach if parsing fails
                let remove_result = (^secret-tool clear service rattler username minioadmin | complete)
                if $remove_result.exit_code == 0 {
                    print "✅ Removed rattler entry for minioadmin"
                } else {
                    print "⚠️ No rattler entries found or failed to remove"
                }
            }
        } else {
            print "No rattler entries found to remove"
        }
    }

    # Remove pixi authentication entries
    if (which pixi | is-not-empty) {
        print ""
        print "Attempting to remove pixi authentication entries..."
        let targets = ["s3://meso-forge", "localhost", "localhost:19000", "127.0.0.1", "minio"]

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
}

# Show help information
def show_help [] {
    print "🔐 MinIO Credential Storage Test Script"
    print ""
    print "USAGE:"
    print "    nu test_credentials.nu [OPTIONS]"
    print ""
    print "OPTIONS:"
    print "    --url URL               MinIO server URL (default: http://localhost:19000)"
    print "    --access-key KEY        MinIO access key (default: minioadmin)"
    print "    --secret-key KEY        MinIO secret key (default: minioadmin)"
    print "    --list-credentials      List stored credentials in system keychain"
    print "    --remove-credentials    Remove stored credentials from system keychain"
    print "    --help                  Show this help message"
    print ""
    print "EXAMPLES:"
    print "    # Test credential storage with defaults"
    print "    nu test_credentials.nu"
    print ""
    print "    # Test with custom credentials"
    print "    nu test_credentials.nu --access-key mykey --secret-key mysecret"
    print ""
    print "    # List stored credentials"
    print "    nu test_credentials.nu --list-credentials"
    print ""
    print "    # Remove stored credentials"
    print "    nu test_credentials.nu --remove-credentials"
    print ""
    print "SECURITY FEATURES:"
    print "    - Uses pixi auth login s3://bucket for cross-platform secure storage"
    print "    - Stores credentials in system keychain via pixi infrastructure"
    print "    - Credentials stored with 'pixi' service name in S3 format"
    print "    - Search for 'pixi' or 's3://' in your system's credential manager"
    print "    - On Linux: Use 'secret-tool search service pixi' to verify storage"
}
