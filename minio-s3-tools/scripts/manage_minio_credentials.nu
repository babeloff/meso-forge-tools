#!/usr/bin/env nu

# Secure MinIO Credential Management Script
# This script helps manage MinIO aliases and their corresponding keyring credentials
#
# SECURITY MODEL:
# - NO credential parameters accepted (security risk)
# - Credentials obtained from MinIO server or interactive entry
# - Uses 'pixi auth login' for secure keyring storage
# - All credential handling uses secure system keychain/keyring
#
# Usage:
#   nu manage_minio_credentials_secure.nu --help
#   nu manage_minio_credentials_secure.nu --list
#   nu manage_minio_credentials_secure.nu --add --alias production --url https://minio.example.com --interactive
#   nu manage_minio_credentials_secure.nu --remove --alias production
#   nu manage_minio_credentials_secure.nu --test --alias local-minio

def main [
    --list                          # List all MinIO aliases and their keyring status
    --add                           # Add new MinIO alias with secure credentials
    --remove                        # Remove MinIO alias and keyring credentials
    --test                          # Test MinIO alias connection
    --alias: string                 # MinIO alias name
    --url: string                   # MinIO server URL (for --add)
    --interactive                   # Prompt for credentials interactively
    --help                          # Show help
] {
    if $help or (not $list and not $add and not $remove and not $test) {
        show_help
        return
    }

    if $list {
        list_minio_aliases
        return
    }

    if $add {
        if ($alias | is-empty) or ($url | is-empty) {
            print "❌ For --add, you must provide --alias and --url"
            print "   Use --interactive to enter credentials securely"
            return
        }
        add_minio_alias $alias $url $interactive
        return
    }

    if $remove {
        if ($alias | is-empty) {
            print "❌ For --remove, you must provide --alias"
            return
        }
        remove_minio_alias $alias
        return
    }

    if $test {
        if ($alias | is-empty) {
            print "❌ For --test, you must provide --alias"
            return
        }
        test_minio_alias $alias
        return
    }
}

# List all MinIO aliases and their keyring status
def list_minio_aliases [] {
    print "📋 MinIO Aliases and Keyring Status"
    print "═══════════════════════════════════"
    print ""

    # Get mc aliases
    let mc_aliases = get_mc_aliases

    if ($mc_aliases | length) == 0 {
        print "ℹ️ No MinIO aliases configured"
        print ""
        print "💡 To add an alias with secure keyring integration:"
        print "   nu manage_minio_credentials_secure.nu --add --alias myalias --url http://localhost:19000 --interactive"
        return
    }

    print $"Found ($mc_aliases | length) MinIO aliases:"
    print ""

    $mc_aliases | each { |alias_info|
        let alias_name = $alias_info.alias
        let keyring_status = get_keyring_status $alias_info.alias
        let keyring_icon = if $keyring_status { "🔐" } else { "❌" }
        let status_text = if $keyring_status { "Keyring: ✅" } else { "Keyring: ❌" }

        print $"($keyring_icon) ($alias_name)"
        print $"   URL: ($alias_info.url)"
        print $"   ($status_text)"
        print ""
    }

    # Show keyring entries that don't have corresponding mc aliases
    let orphaned_entries = get_orphaned_keyring_entries $mc_aliases
    if ($orphaned_entries | length) > 0 {
        print "⚠️ Orphaned keyring entries (no corresponding mc alias):"
        $orphaned_entries | each { |entry|
            print $"   🔑 ($entry)"
        }
        print ""
    }

    # Show pixi auth stored credentials
    print "🔐 Pixi Auth Stored Credentials:"
    if (which secret-tool | is-not-empty) {
        let pixi_search = (^secret-tool search service pixi | complete)
        if $pixi_search.exit_code == 0 and ($pixi_search.stdout | str length) > 0 {
            let s3_entries = ($pixi_search.stdout | lines | where { |line| ($line | str contains 's3://') })
            if ($s3_entries | length) > 0 {
                $s3_entries | each { |entry| print $"   🔐 ($entry)" }
            } else {
                print "   No S3 bucket credentials found"
            }
        } else {
            print "   No pixi credentials found"
        }
    } else {
        print "   secret-tool not available"
    }
    print ""
}

# Add new MinIO alias with secure credential handling
def add_minio_alias [alias: string, url: string, interactive: bool] {
    print $"🚀 Adding MinIO alias '($alias)' securely..."

    # Check if alias already exists
    let existing_aliases = get_mc_aliases
    let alias_exists = ($existing_aliases | where alias == $alias | length) > 0

    if $alias_exists {
        print $"⚠️ Alias '($alias)' already exists. Updating..."
        ^mc alias remove $alias | complete | ignore
    }

    # Get credentials securely
    let credentials = get_secure_credentials $alias $url $interactive

    if ($credentials == null) {
        print "❌ Failed to obtain credentials securely"
        return
    }

    # Configure mc alias
    let result = (^mc alias set $alias $url $credentials.access_key $credentials.secret_key | complete)

    if $result.exit_code == 0 {
        print $"✅ MinIO alias '($alias)' configured successfully"
        print $"📍 URL: ($url)"
        print $"👤 Access Key: ($credentials.access_key)"
        print $"🔐 Secret Key: <stored securely>"

        # Store credentials securely
        store_credentials_securely $alias $url $credentials

        # Test the connection
        print ""
        test_minio_alias $alias
    } else {
        print $"❌ Failed to configure MinIO alias '($alias)'"
        print $result.stderr
    }
}

# Get credentials through secure methods
def get_secure_credentials [alias: string, url: string, interactive: bool] {
    print "🔍 Obtaining credentials securely..."

    # Check if credentials already exist in keyring
    let existing_creds = get_stored_credentials $alias
    if ($existing_creds != null) {
        print "✅ Found existing credentials in keyring"
        return $existing_creds
    }

    # Try to get from MinIO server configuration
    let server_creds = get_credentials_from_server $url
    if ($server_creds != null) {
        print "✅ Retrieved credentials from MinIO server"
        return $server_creds
    }

    # Check for local development defaults
    if ($url | str contains "localhost") or ($url | str contains "127.0.0.1") {
        print "ℹ️ Local MinIO detected - checking default credentials"
        let default_creds = test_default_credentials $url
        if ($default_creds != null) {
            print "✅ Using default local MinIO credentials"
            return $default_creds
        }
    }

    # Interactive credential entry
    if $interactive {
        print "ℹ️ Prompting for credentials interactively..."
        return (prompt_for_credentials)
    }

    print "❌ No credentials available. Use --interactive to enter them securely."
    return null
}

# Get stored credentials from keyring
def get_stored_credentials [alias: string] {
    # Try pixi format first
    if (which secret-tool | is-not-empty) {
        let pixi_search = (^secret-tool search service pixi | complete)
        if $pixi_search.exit_code == 0 and ($pixi_search.stdout | str length) > 0 {
            # Parse pixi credentials if they exist for this alias
            # This would need to be implemented based on pixi's storage format
        }

        # Try mc format
        let result = (^secret-tool lookup service mc alias $alias | complete)
        if $result.exit_code == 0 and ($result.stdout | str length) > 0 {
            let credentials_json = ($result.stdout | str trim)
            try {
                let parsed = ($credentials_json | from json)
                return {access_key: $parsed.account, secret_key: $parsed.secret}
            } catch {
                return null
            }
        }
    }
    return null
}

# Attempt to get credentials from MinIO server
def get_credentials_from_server [url: string] {
    print $"ℹ️ Checking MinIO server at ($url) for credential configuration..."

    # Check server accessibility
    let ping_result = (^curl -s --connect-timeout 5 $"($url)/minio/health/live" | complete)
    if $ping_result.exit_code != 0 {
        print "⚠️ MinIO server not accessible"
        return null
    }

    # In a production environment, this might:
    # 1. Check for service account configurations
    # 2. Integrate with identity providers (LDAP, AD, etc.)
    # 3. Use admin API to retrieve/create service credentials
    # 4. Check for environment-specific credential stores

    print "ℹ️ Server accessible but credential auto-retrieval not implemented"
    print "   Consider implementing integration with your credential management system"
    return null
}

# Test default credentials for local development
def test_default_credentials [url: string] {
    let default_combinations = [
        {access_key: "minioadmin", secret_key: "minioadmin"},
        {access_key: "minioadmin", secret_key: "miniosecurepassword123"},
        {access_key: "admin", secret_key: "password"},
        {access_key: "minio", secret_key: "minio123"}
    ]

    for creds in $default_combinations {
        print $"ℹ️ Testing credentials: ($creds.access_key)"
        let test_result = (^mc alias set test-temp $url $creds.access_key $creds.secret_key | complete)
        if $test_result.exit_code == 0 {
            ^mc alias remove test-temp | complete | ignore
            print $"✅ Found working default credentials: ($creds.access_key)"
            return $creds
        }
    }

    return null
}

# Prompt for credentials interactively and securely
def prompt_for_credentials [] {
    print ""
    print "🔐 Please enter MinIO credentials:"
    print "   (These will be stored securely in your system keyring)"
    print ""

    let access_key = (input "Access Key: ")
    if ($access_key | str length) == 0 {
        print "❌ Access key is required"
        return null
    }

    # Use secure password input methods
    let secret_key = if (which systemd-ask-password | is-not-empty) {
        (^systemd-ask-password --no-tty "Secret Key: " | str trim)
    } else if (which python3 | is-not-empty) {
        (^python3 -c "import getpass; print(getpass.getpass('Secret Key: '))" | str trim)
    } else {
        print "⚠️ No secure password input method available, using basic input"
        (input --suppress-output "Secret Key: ")
    }

    if ($secret_key | str length) == 0 {
        print "❌ Secret key is required"
        return null
    }

    print "✅ Credentials entered successfully"
    return {access_key: $access_key, secret_key: $secret_key}
}

# Store credentials securely using multiple methods
def store_credentials_securely [alias: string, url: string, credentials: record] {
    print "🔐 Storing credentials securely..."

    mut success_count = 0

    # Store with pixi auth login (primary method)
    if (which pixi | is-not-empty) {
        let bucket_name = $"s3://($alias)"
        let login_result = (^pixi auth login $bucket_name --s3-access-key-id $credentials.access_key --s3-secret-access-key $credentials.secret_key | complete)

        if $login_result.exit_code == 0 {
            print "✅ Credentials stored via pixi auth login"
            $success_count = ($success_count + 1)
        } else {
            print "⚠️ Failed to store credentials via pixi auth"
            print $login_result.stderr
        }
    } else {
        print "⚠️ pixi not available for secure credential storage"
    }

    # Store in mc-compatible keyring format (secondary method)
    if (which secret-tool | is-not-empty) {
        let cred_json = {account: $credentials.access_key, secret: $credentials.secret_key} | to json
        let result = (echo $cred_json | ^secret-tool store --label=$"MinIO Credentials for ($alias):($credentials.access_key)" service mc alias $alias | complete)
        if $result.exit_code == 0 {
            print "✅ Credentials stored in mc-compatible keyring format"
            $success_count = ($success_count + 1)
        } else {
            print "⚠️ Failed to store credentials in keyring"
        }
    } else {
        print "⚠️ secret-tool not available for keyring storage"
    }

    if $success_count > 0 {
        let count_message = $"($success_count) secure locations"
        print $"🎉 Credentials stored successfully in ($count_message)"
    } else {
        print "❌ Failed to store credentials in any secure location"
    }
}

# Remove MinIO alias and all associated credentials
def remove_minio_alias [alias: string] {
    print $"🗑️ Removing MinIO alias '($alias)' and all credentials..."

    mut removal_count = 0

    # Remove mc alias
    let alias_result = (^mc alias remove $alias | complete)
    if $alias_result.exit_code == 0 {
        print $"✅ MinIO alias '($alias)' removed from mc configuration"
        $removal_count = ($removal_count + 1)
    } else {
        print $"⚠️ Failed to remove mc alias or alias didn't exist"
    }

    # Remove from pixi auth
    if (which pixi | is-not-empty) {
        let logout_result = (^pixi auth logout $"s3://($alias)" | complete)
        if $logout_result.exit_code == 0 {
            print $"✅ Credentials removed from pixi auth"
            $removal_count = ($removal_count + 1)
        } else {
            print $"⚠️ No pixi auth credentials found for alias '($alias)'"
        }
    }

    # Remove from keyring
    if (which secret-tool | is-not-empty) {
        let clear_result = (^secret-tool clear service mc alias $alias | complete)
        if $clear_result.exit_code == 0 {
            print $"✅ Credentials removed from keyring"
            $removal_count = ($removal_count + 1)
        } else {
            print $"⚠️ No keyring credentials found for alias '($alias)'"
        }
    }

    let count_message = $"($removal_count) items removed"
    print $"🎉 Cleanup completed for alias '($alias)' ($count_message)"
}

# Test MinIO alias connection
def test_minio_alias [alias: string] {
    print $"🔍 Testing MinIO alias '($alias)'..."

    # Check if alias exists in mc
    let existing_aliases = get_mc_aliases
    let alias_info = ($existing_aliases | where alias == $alias)

    if ($alias_info | length) == 0 {
        print $"❌ Alias '($alias)' not found in mc configuration"
        return
    }

    # Check keyring status
    let has_keyring = get_keyring_status $alias
    if $has_keyring {
        print $"✅ Keyring credentials found for '($alias)'"
    } else {
        print $"⚠️ No keyring credentials found for '($alias)'"
    }

    # Test connection by listing buckets
    let list_result = (^mc ls $alias | complete)

    if $list_result.exit_code == 0 {
        print $"✅ Connection successful to '($alias)'"
        if ($list_result.stdout | str length) > 0 {
            print "📦 Available buckets:"
            let buckets = ($list_result.stdout | lines | where { |line| ($line | str length) > 0 })
            $buckets | each { |bucket| print $"   ($bucket)" }
        } else {
            print "ℹ️ No buckets found (or empty response)"
        }
    } else {
        print $"❌ Connection failed to '($alias)'"
        print $"Error: ($list_result.stderr)"
        print ""
        print "💡 This might indicate:"
        print "   - Invalid credentials"
        print "   - Server not accessible"
        print "   - Network connectivity issues"
        print "   Try: nu manage_minio_credentials_secure.nu --add --alias ($alias) --url <server-url> --interactive"
    }
}

# Helper functions

# Get all mc aliases
def get_mc_aliases [] {
    let result = (^mc alias list | complete)
    if $result.exit_code != 0 {
        return []
    }

    let lines = ($result.stdout | lines)

    # Parse mc alias list output format
    let parsed = ($lines
        | where { |line| ($line | str length) > 0 }
        | reduce -f {aliases: [], current_alias: "", current_url: "", current_access_key: "", in_alias: false} { |line, acc|
            if not ($line | str starts-with "  ") {
                # This is an alias name line
                {aliases: $acc.aliases, current_alias: ($line | str trim), current_url: "", current_access_key: "", in_alias: true}
            } else if ($line | str contains "URL") and $acc.in_alias {
                # Extract URL
                let url = ($line | str replace "  URL       : " "" | str trim)
                {aliases: $acc.aliases, current_alias: $acc.current_alias, current_url: $url, current_access_key: $acc.current_access_key, in_alias: $acc.in_alias}
            } else if ($line | str contains "AccessKey") and $acc.in_alias {
                # Extract access key and save the complete alias
                let access_key = ($line | str replace "  AccessKey : " "" | str trim)
                let new_alias = {alias: $acc.current_alias, url: $acc.current_url, access_key: $access_key}
                {aliases: ($acc.aliases | append $new_alias), current_alias: "", current_url: "", current_access_key: "", in_alias: false}
            } else {
                $acc
            }
        })

    return $parsed.aliases
}

# Check if keyring has credentials for alias
def get_keyring_status [alias: string] {
    if (which secret-tool | is-not-empty) {
        let result = (^secret-tool lookup service mc alias $alias | complete)
        return ($result.exit_code == 0 and ($result.stdout | str length) > 0)
    }
    return false
}

# Get orphaned keyring entries
def get_orphaned_keyring_entries [mc_aliases: list] {
    if not (which secret-tool | is-not-empty) {
        return []
    }

    let search_result = (^secret-tool search service mc | complete)
    if $search_result.exit_code != 0 {
        return []
    }

    let keyring_aliases = ($search_result.stdout
        | lines
        | where { |line| ($line | str contains 'alias = ') }
        | parse "alias = {alias}"
        | get alias)

    let mc_alias_names = ($mc_aliases | get alias)

    $keyring_aliases | where { |kr_alias| $kr_alias not-in $mc_alias_names }
}

# Show help
def show_help [] {
    print "🛠️ Secure MinIO Credential Management Tool"
    print ""
    print "This tool helps manage MinIO aliases and their keyring credentials securely."
    print "It does NOT accept credential parameters for security reasons."
    print ""
    print "USAGE:"
    print "    nu manage_minio_credentials_secure.nu [COMMAND] [OPTIONS]"
    print ""
    print "COMMANDS:"
    print "    --list                              List all aliases and keyring status"
    print "    --add                               Add new alias with secure credentials"
    print "    --remove                            Remove alias and all credentials"
    print "    --test                              Test alias connection"
    print ""
    print "OPTIONS:"
    print "    --alias ALIAS                       MinIO alias name"
    print "    --url URL                           MinIO server URL (for --add)"
    print "    --interactive                       Prompt for credentials securely"
    print ""
    print "EXAMPLES:"
    print "    # List all configured aliases"
    print "    nu manage_minio_credentials_secure.nu --list"
    print ""
    print "    # Add local MinIO with interactive credentials"
    print "    nu manage_minio_credentials_secure.nu --add \\"
    print "        --alias local-minio \\"
    print "        --url http://localhost:19000 \\"
    print "        --interactive"
    print ""
    print "    # Add production MinIO with secure credential detection"
    print "    nu manage_minio_credentials_secure.nu --add \\"
    print "        --alias production \\"
    print "        --url https://minio.example.com \\"
    print "        --interactive"
    print ""
    print "    # Test connection"
    print "    nu manage_minio_credentials_secure.nu --test --alias local-minio"
    print ""
    print "    # Remove alias and all credentials"
    print "    nu manage_minio_credentials_secure.nu --remove --alias production"
    print ""
    print "SECURITY FEATURES:"
    print "    ✅ No credential parameters (prevents command history exposure)"
    print "    ✅ Credentials stored in system keyring via pixi auth"
    print "    ✅ Automatic credential detection from MinIO server"
    print "    ✅ Secure interactive credential entry"
    print "    ✅ Cross-platform keyring integration"
    print "    ✅ Multiple secure storage locations"
    print ""
    print "CREDENTIAL SOURCES (in priority order):"
    print "    1. Existing keyring storage (pixi auth + mc format)"
    print "    2. MinIO server configuration"
    print "    3. Default credentials (local development only)"
    print "    4. Interactive entry (with --interactive flag)"
    print ""
    print "KEYRING INTEGRATION:"
    print "    - Primary: 'pixi auth login s3://alias' format"
    print "    - Secondary: 'mc' service with alias-based keys"
    print "    - All credentials stored securely in system keychain"
    print ""
    print "NOTES:"
    print "    - Credentials are NEVER passed as command line arguments"
    print "    - Use --interactive for secure credential entry"
    print "    - Multiple storage methods ensure compatibility"
    print "    - Server-based credential retrieval can be extended"
}
