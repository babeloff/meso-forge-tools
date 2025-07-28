#!/usr/bin/env nu

# Test built packages
def main [
    --platform (-p): string = ""  # Test packages for specific platform
    --package (-k): string = ""   # Test specific package
] {
    print "🧪 Testing built packages..."

    let output_dirs = if ($platform | is-empty) {
        ls output | where type == dir | get name
    } else {
        let platform_dir = $"output/($platform)"
        if ($platform_dir | path exists) {
            [$platform_dir]
        } else {
            print $"❌ No packages found for platform: ($platform)"
            return
        }
    }

    for dir in $output_dirs {
        let platform_name = $dir | path basename
        print $"\n🔍 Testing packages for ($platform_name)..."

        let packages = ls $dir | where name =~ '\.(conda|tar\.bz2)$' | get name

        if ($packages | length) == 0 {
            print $"  ℹ️  No packages found in ($dir)"
            continue
        }

        for package_file in $packages {
            let package_name = $package_file | path basename | str replace -r '\.(conda|tar\.bz2)$' ""

            if (not ($package | is-empty)) and ($package_name !~ $package) {
                continue
            }

            print $"  Testing: ($package_name)"

            # Basic package validation
            try {
                let file_size = ls $package_file | get size | first
                let file_type = if ($package_file | str ends-with ".conda") { "conda" } else { "tar.bz2" }

                if $file_size > 1kb {
                    print $"    ✅ Package exists and has reasonable size"
                    print $"      Size: ($file_size)"
                    print $"      Format: ($file_type)"

                    # Basic file type validation
                    let file_info = file $package_file
                    if ($file_info | str contains "Zip") or ($file_info | str contains "bzip2") {
                        print $"    ✅ Package format appears valid"
                    } else {
                        print $"    ⚠️  Package format may be unexpected"
                        print $"      File info: ($file_info)"
                    }
                } else {
                    print $"    ❌ Package appears to be too small"
                    print $"      Size: ($file_size)"
                }
            } catch {
                print $"    ❌ Package validation failed - could not access package file"
            }
        }
    }

    print "🧪 Package testing complete!"
}
