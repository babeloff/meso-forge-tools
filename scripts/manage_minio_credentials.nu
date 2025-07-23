#!/usr/bin/env nu

# MinIO Credential Management Script
# This script helps manage MinIO aliases and their corresponding keyring credentials
#
# Usage:
#   nu manage_minio_credentials.nu --help
#   nu manage_minio_credentials.nu --list
#   nu manage_minio_credentials.nu --add --alias production --url https://minio.example.com --access-key mykey --secret-key mysecret
#   nu manage_minio_credentials.nu --remove --alias production
#   nu manage_minio_credentials.nu --test --alias local-minio

def main [
    --list                          # List all MinIO aliases and their keyring status
    --add                           # Add new MinIO alias with keyring credentials
    --remove                        # Remove MinIO alias and keyring credentials
    --test                          # Test MinIO alias connection
    --alias: string                 # MinIO alias name
    --url: string                   # MinIO server URL (for --add)
    --access-key: string            # Access key (for --add)
    --secret-key: string            # Secret key (for --add)
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
        if ($alias | is-empty) or ($url | is-empty) or ($access_key | is-empty) or ($secret_key | is-empty) {
            print "❌ For --add, you must provide --alias, --url, --access-key, and --secret-key"
            return
        }
        add_minio_alias $alias $url $access_key $secret_key
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
        print "💡 To add an alias with keyring integration:"
        print "   nu manage_minio_credentials.nu --add --alias myalias --url http://localhost:19000 --access-key mykey --secret-key mysecret"
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
}

# Add new MinIO alias with keyring credentials
def add_minio_alias [alias: string, url: string, access_key: string, secret_key: string] {
    print $"🚀 Adding MinIO alias '($alias)'..."

    # Check if alias already exists
    let existing_aliases = get_mc_aliases
    let alias_exists = ($existing_aliases | where alias == $alias | length) > 0

    if $alias_exists {
        print $"⚠️ Alias '($alias)' already exists. Updating..."
        ^mc alias remove $alias | complete | ignore
    }

    # Store credentials in keyring first
    print $"ℹ️ Storing credentials in keyring for alias '($alias)' account '($access_key)'..."
    if (store_keyring_password $alias $access_key $secret_key) {
        print "✅ Credentials stored in GNOME keyring"
    } else {
        print "❌ Failed to store credentials in keyring"
        return
    }

    # Configure mc alias
    let result = (^mc alias set $alias $url $access_key $secret_key | complete)

    if $result.exit_code == 0 {
        print $"✅ MinIO alias '($alias)' configured successfully"
        print $"📍 URL: ($url)"
        print $"👤 Access Key: ($access_key)"
        print $"🔐 Secret Key: <stored in keyring>"

        # Test the connection
        print ""
        test_minio_alias $alias
    } else {
        print $"❌ Failed to configure MinIO alias '($alias)'"
        print $result.stderr

        # Clean up keyring entry on failure
        clear_keyring_password $alias
    }
}

# Remove MinIO alias and keyring credentials
def remove_minio_alias [alias: string] {
    print $"🗑️ Removing MinIO alias '($alias)'..."

    # Check if alias exists
    let existing_aliases = get_mc_aliases
    let alias_exists = ($existing_aliases | where alias == $alias | length) > 0

    if not $alias_exists {
        print $"⚠️ Alias '($alias)' does not exist in mc configuration"
    } else {
        # Remove mc alias
        let result = (^mc alias remove $alias | complete)
        if $result.exit_code == 0 {
            print $"✅ MinIO alias '($alias)' removed from mc configuration"
        } else {
            print $"⚠️ Failed to remove mc alias: ($result.stderr)"
        }
    }

    # Remove keyring credentials
    if (clear_keyring_password $alias) {
        print $"✅ Credentials removed from keyring for alias '($alias)'"
    } else {
        print $"⚠️ No keyring credentials found for alias '($alias)' or failed to remove"
    }

    print $"🎉 Cleanup completed for alias '($alias)'"
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
        | where { |line| ($line | str contains "alias = ") }
        | parse "alias = {alias}"
        | get alias)

    let mc_alias_names = ($mc_aliases | get alias)

    $keyring_aliases | where { |kr_alias| $kr_alias not-in $mc_alias_names }
}

# Store password in keyring
def store_keyring_password [alias: string, account: string, password: string] {
    if (which secret-tool | is-not-empty) {
        let credentials = {account: $account, secret: $password} | to json
        let result = (echo $credentials | ^secret-tool store --label=$"MinIO Credentials for ($alias):($account)" service mc alias $alias | complete)
        return ($result.exit_code == 0)
    }
    return false
}

# Clear password from keyring
def clear_keyring_password [alias: string] {
    if (which secret-tool | is-not-empty) {
        let result = (^secret-tool clear service mc alias $alias | complete)
        return ($result.exit_code == 0)
    }
    return false
}

# Show help
def show_help [] {
    print "🛠️ MinIO Credential Management Tool"
    print ""
    print "This tool helps manage MinIO aliases and their keyring credentials."
    print "It links 'mc alias' entries with GNOME keyring for secure password storage."
    print ""
    print "USAGE:"
    print "    nu manage_minio_credentials.nu [COMMAND] [OPTIONS]"
    print ""
    print "COMMANDS:"
    print "    --list                              List all aliases and keyring status"
    print "    --add                               Add new alias with keyring integration"
    print "    --remove                            Remove alias and keyring credentials"
    print "    --test                              Test alias connection"
    print ""
    print "OPTIONS:"
    print "    --alias ALIAS                       MinIO alias name"
    print "    --url URL                           MinIO server URL (for --add)"
    print "    --access-key KEY                    Access key (for --add)"
    print "    --secret-key SECRET                 Secret key (for --add)"
    print ""
    print "EXAMPLES:"
    print "    # List all configured aliases"
    print "    nu manage_minio_credentials.nu --list"
    print ""
    print "    # Add local MinIO"
    print "    nu manage_minio_credentials.nu --add \\"
    print "        --alias local-minio \\"
    print "        --url http://localhost:19000 \\"
    print "        --access-key minioadmin \\"
    print "        --secret-key miniosecurepassword123"
    print ""
    print "    # Add production MinIO"
    print "    nu manage_minio_credentials.nu --add \\"
    print "        --alias production \\"
    print "        --url https://minio.example.com \\"
    print "        --access-key prod_access_key \\"
    print "        --secret-key prod_secret_key"
    print ""
    print "    # Test connection"
    print "    nu manage_minio_credentials.nu --test --alias local-minio"
    print ""
    print "    # Remove alias and credentials"
    print "    nu manage_minio_credentials.nu --remove --alias production"
    print ""
    print "KEYRING INTEGRATION:"
    print "    Credentials are stored in GNOME keyring with the format:"
    print "    service=mc, alias=ALIAS_NAME"
    print ""
    print "    You can manually retrieve credentials with:"
    print "    secret-tool lookup service mc alias ALIAS_NAME"
    print ""
    print "    This links mc aliases with keyring entries for secure credential management."
}
