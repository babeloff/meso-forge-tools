#!/usr/bin/env nu

# Minimal MinIO initialization script for testing
# This script does the essential MinIO setup with proper bucket existence checking

def main [
    --url: string = "http://localhost:19000",
    --access-key: string = "minioadmin",
    --bucket: string = "meso-forge",
    --alias: string = "local-minio"
] {
    print "🚀 Minimal MinIO initialization..."
    print ""

    # Get secret from keyring
    let secret_key = get_keyring_password $access_key
    print $"ℹ️ Using credentials: ($access_key) / <password from keyring>"

    # Step 1: Check if mc is available
    if not (which mc | is-not-empty) {
        print "❌ MinIO client (mc) not found"
        return
    }
    print "✅ MinIO client (mc) available"

    # Step 2: Configure mc alias
    print $"ℹ️ Configuring alias '($alias)'..."

    # Remove existing alias if present
    ^mc alias remove $alias | complete | ignore

    # Add new alias
    let alias_result = (^mc alias set $alias $url $access_key $secret_key | complete)

    if $alias_result.exit_code != 0 {
        print "❌ Failed to configure mc alias"
        print $alias_result.stderr
        return
    }
    print "✅ MC alias configured"

    # Step 3: Check bucket existence before creating
    print $"ℹ️ Checking if bucket '($bucket)' exists..."

    let bucket_list = (^mc ls $alias | complete)

    if $bucket_list.exit_code != 0 {
        print "❌ Failed to list buckets"
        print $bucket_list.stderr
        return
    }

    let bucket_exists = ($bucket_list.stdout | str contains $"($bucket)/")

    if $bucket_exists {
        print $"ℹ️ Bucket '($bucket)' already exists - skipping creation"
    } else {
        print $"ℹ️ Creating bucket '($bucket)'..."
        let create_result = (^mc mb $"($alias)/($bucket)" | complete)

        if $create_result.exit_code == 0 {
            print $"✅ Bucket '($bucket)' created successfully"
        } else {
            print "❌ Failed to create bucket"
            print $create_result.stderr
            return
        }
    }

    # Step 4: Set up pixi auth for publishing
    print "ℹ️ Setting up pixi authentication..."
    let pixi_result = (^pixi auth login $"s3://($bucket)" --s3-access-key-id $access_key --s3-secret-access-key $secret_key | complete)

    if $pixi_result.exit_code == 0 {
        print "✅ Pixi authentication configured"
    } else {
        print "⚠️ Pixi authentication failed (this might be okay)"
        print $pixi_result.stderr
    }

    # Step 5: Test the setup
    print "ℹ️ Testing setup..."
    let test_result = (^mc ls $"($alias)/($bucket)" | complete)

    if $test_result.exit_code == 0 {
        print "✅ Setup test successful!"
        print $"📋 Bucket contents: ($test_result.stdout)"
    } else {
        print "⚠️ Setup test failed"
        print $test_result.stderr
    }

    print ""
    print "🎉 MinIO initialization completed!"
    print $"📍 Alias: ($alias) -> ($url)"
    print $"📦 Bucket: ($bucket)"
}

# Get password from keyring
def get_keyring_password [username: string] {
    if (which secret-tool | is-not-empty) {
        let result = (^secret-tool lookup service mc account $username | complete)
        if $result.exit_code == 0 and ($result.stdout | str length) > 0 {
            return ($result.stdout | str trim)
        }
    }
    # Fallback to default if keyring fails
    return "miniosecurepassword123"
}
