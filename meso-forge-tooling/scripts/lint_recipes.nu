#!/usr/bin/env nu

# Lint all recipe files
def main [
    --fix (-f)  # Attempt to fix issues automatically
] {
    print "🔍 Linting recipe files..."

    let recipes = find_all_recipes

    if ($recipes | length) == 0 {
        print "ℹ️  No recipe files found"
        return
    }

    print $"Found ($recipes | length) recipe files"

    mut total_issues = 0

    for recipe in $recipes {
        let package_name = $recipe | path dirname | path basename
        print $"\n📋 Linting: ($package_name)"

        let issues = lint_recipe $recipe
        $total_issues = $total_issues + ($issues | length)

        if ($issues | length) == 0 {
            print $"  ✅ No issues found"
        } else {
            print $"  ⚠️  Found ($issues | length) issues:"
            for issue in $issues {
                print $"    - ($issue)"
            }

            if $fix {
                print $"  🔧 Attempting to fix issues..."
                try {
                    fix_recipe_issues $recipe $issues
                    print $"  ✅ Issues fixed"
                } catch {
                    print $"  ❌ Could not fix all issues automatically"
                }
            }
        }
    }

    print $"\n📊 Linting complete! Total issues found: ($total_issues)"

    if $total_issues > 0 and not $fix {
        print "💡 Run with --fix to attempt automatic fixes"
    }
}

# Find all recipe files
def find_all_recipes [] {
    glob "pkgs/**/recipe.yaml"
}

# Lint a single recipe file
def lint_recipe [recipe_path: string] {
    let issues_result = try {
        let recipe = open $recipe_path --raw | from yaml
        let content = open $recipe_path --raw

        let required_issues = [
            (if ($recipe.package?.name? | is-empty) { "Missing package.name" } else { null }),
            (if ($recipe.package?.version? | is-empty) { "Missing package.version" } else { null }),
            (if ($recipe.source? | is-empty) { "Missing source section" } else { null }),
            (if ($recipe.build? | is-empty) { "Missing build section" } else { null })
        ] | compact

        let format_issues = [
            (if ($content | str contains "\t") { "Contains tabs (should use spaces)" } else { null }),
            (if ($content | str contains "  \n") { "Contains trailing whitespace" } else { null })
        ] | compact

        $required_issues ++ $format_issues
    } catch {
        ["Invalid YAML syntax"]
    }

    $issues_result
}

# Fix common recipe issues
def fix_recipe_issues [recipe_path: string, issues: list] {
    let content = open $recipe_path --raw

    # Fix tabs to spaces
    let fixed_content = $content | str replace -a "\t" "  "

    # Remove trailing whitespace
    let final_content = $fixed_content | str replace -ra "[ ]+\n" "\n"

    $final_content | save -f $recipe_path
}
