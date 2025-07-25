#!/usr/bin/env nu

# meso-forge - Multi-package build suite wrapper (Nushell version)
# Comprehensive wrapper for all meso-forge-tooling nushell scripts and Python utilities

def main [
    command?: string = "help"  # Command to execute
    ...args: string           # Additional arguments passed to the command
] {
    # Determine the tooling root directory
    let tooling_root = get_tooling_root
    let scripts_dir = $tooling_root | path join "scripts"
    let skeletons_dir = $tooling_root | path join "pkg-skeletons"

    # Environment setup
    $env.MESO_FORGE_TOOLING_ROOT = $tooling_root

    # Command dispatcher
    match $command {
        # Build commands
        "build" | "build-pkg" => {
            if ($args | length) == 0 {
                print $"(ansi red)Error: Package name required for build command(ansi reset)"
                print $"Usage: meso-forge build <package-name> [options]"
                print $"       meso-forge build-all [options]"
                exit 1
            }

            let package_name = $args.0
            let recipe_path = $"./pkgs/($package_name)/recipe.yaml"

            if not ($recipe_path | path exists) {
                print $"(ansi red)Error: Recipe not found at ($recipe_path)(ansi reset)"
                print "Available packages:"
                list_local_packages
                exit 1
            }

            let remaining_args = $args | skip 1
            run_nu_script $scripts_dir "build_single.nu" ["--recipe" $recipe_path ...$remaining_args]
        }

        "build-all" => {
            run_nu_script $scripts_dir "build_all.nu" $args
        }

        "build-noarch" => {
            run_nu_script $scripts_dir "build_noarch.nu" $args
        }

        "build-platform" => {
            run_nu_script $scripts_dir "build_platform.nu" $args
        }

        "build-single" => {
            if ($args | length) < 2 or ($args.0 != "--recipe") {
                print $"(ansi red)Error: Recipe path required(ansi reset)"
                print $"Usage: meso-forge build-single --recipe <path/to/recipe.yaml> [options]"
                exit 1
            }
            run_nu_script $scripts_dir "build_single.nu" $args
        }

        # Publishing commands
        "publish" => {
            run_nu_script $scripts_dir "package_publish.nu" $args
        }

        "publish-pd" => {
            run_nu_script $scripts_dir "package_publish.nu" ["--mode" "pd" ...$args]
        }

        "publish-s3" => {
            run_nu_script $scripts_dir "package_publish.nu" ["--mode" "s3" ...$args]
        }

        "publish-local" => {
            run_nu_script $scripts_dir "package_publish.nu" [
                "--mode" "s3"
                "--channel" "s3://pixi-local/meso-forge"
                "--url" "http://localhost:19000"
                ...$args
            ]
        }

        # Testing commands
        "test" | "test-packages" => {
            run_nu_script $scripts_dir "test_packages.nu" $args
        }

        "test-package" => {
            if ($args | length) == 0 {
                print $"(ansi red)Error: Package name required(ansi reset)"
                print $"Usage: meso-forge test-package <package-name> [options]"
                exit 1
            }
            run_nu_script $scripts_dir "test_package.nu" $args
        }

        # Package management commands
        "check" | "check-package" => {
            run_nu_script $scripts_dir "check_package_exists.nu" $args
        }

        "retract" => {
            run_nu_script $scripts_dir "package_retract.nu" $args
        }

        # Quality assurance commands
        "lint" | "lint-recipes" => {
            run_nu_script $scripts_dir "lint_recipes.nu" $args
        }

        "analyze" | "analyze-recipes" => {
            run_py_script $scripts_dir "analyze_recipes.py" $args
        }

        "generate-readmes" | "readmes" => {
            run_py_script $scripts_dir "generate_readmes.py" $args
        }

        # Version control commands
        "version" | "version-update" => {
            run_py_script $scripts_dir "version_ctl.py" $args
        }

        "test-plugins" => {
            run_py_script $scripts_dir "test_plugins.py" $args
        }

        # Package initialization commands
        "init" | "init-package" => {
            if ($args | length) < 2 {
                print $"(ansi red)Error: Both skeleton type and package name required(ansi reset)"
                print $"Usage: meso-forge init-package <skeleton-type> <package-name>"
                print "Available skeletons:"
                list_skeletons $skeletons_dir
                exit 1
            }

            let skeleton_type = $args.0
            let package_name = $args.1
            let source_dir = $skeletons_dir | path join $skeleton_type
            let target_dir = $"./pkgs/($package_name)"

            if not ($source_dir | path exists) {
                print $"(ansi red)Error: Skeleton type '($skeleton_type)' not found(ansi reset)"
                print "Available skeletons:"
                list_skeletons $skeletons_dir
                exit 1
            }

            if ($target_dir | path exists) {
                print $"(ansi red)Error: Package '($package_name)' already exists at ($target_dir)(ansi reset)"
                exit 1
            }

            mkdir "./pkgs"
            cp -r $source_dir $target_dir
            print $"✅ Created package skeleton '($package_name)' from '($skeleton_type)'"
            print $"📁 Package created at: ($target_dir)"
            print "📝 Next steps:"
            print $"   1. Edit ($target_dir)/recipe.yaml"
            print $"   2. Run: meso-forge build ($package_name)"
        }

        # Utility commands
        "list" | "list-packages" => {
            print "Available packages:"
            list_local_packages
        }

        "skeletons" | "list-skeletons" => {
            print "Available package skeletons:"
            list_skeletons $skeletons_dir
        }

        "scripts" | "list-scripts" => {
            print "Available nushell scripts:"
            list_nu_scripts $scripts_dir
            print ""
            print "Available Python scripts:"
            list_py_scripts $scripts_dir
        }

        # Information commands
        "config" | "info" => {
            show_config $tooling_root $scripts_dir $skeletons_dir
        }

        # Help commands
        "help" | "--help" | "-h" => {
            show_help $tooling_root
        }

        # Direct script execution (for advanced users)
        "run" => {
            if ($args | length) == 0 {
                print $"(ansi red)Error: Script name required(ansi reset)"
                print $"Usage: meso-forge run <script-name> [args...]"
                print "Available scripts:"
                main "list-scripts"
                exit 1
            }

            let script_name = $args.0
            let script_args = $args | skip 1

            # Try .nu extension first, then .py
            let nu_script = $scripts_dir | path join $"($script_name).nu"
            let py_script = $scripts_dir | path join $"($script_name).py"
            let exact_script = $scripts_dir | path join $script_name

            if ($nu_script | path exists) {
                run_nu_script $scripts_dir $"($script_name).nu" $script_args
            } else if ($py_script | path exists) {
                run_py_script $scripts_dir $"($script_name).py" $script_args
            } else if ($exact_script | path exists) {
                if ($script_name | str ends-with ".nu") {
                    run_nu_script $scripts_dir $script_name $script_args
                } else if ($script_name | str ends-with ".py") {
                    run_py_script $scripts_dir $script_name $script_args
                } else {
                    print $"(ansi red)Error: Unknown script type: ($script_name)(ansi reset)"
                    exit 1
                }
            } else {
                print $"(ansi red)Error: Script not found: ($script_name)(ansi reset)"
                print "Available scripts:"
                main "list-scripts"
                exit 1
            }
        }

        _ => {
            print $"(ansi red)Unknown command: ($command)(ansi reset)"
            print $"Use 'meso-forge help' for usage information"
            print $"Use 'meso-forge list-scripts' to see all available scripts"
            exit 1
        }
    }
}

# Helper function to determine tooling root directory
def get_tooling_root [] {
    if ($env.MESO_FORGE_TOOLING_ROOT? | is-not-empty) and ($env.MESO_FORGE_TOOLING_ROOT | path exists) {
        $env.MESO_FORGE_TOOLING_ROOT
    } else if ($env.CONDA_PREFIX? | is-not-empty) and ([$env.CONDA_PREFIX "share" "meso-forge-tooling"] | path join | path exists) {
        [$env.CONDA_PREFIX "share" "meso-forge-tooling"] | path join
    } else if ("./meso-forge-tooling" | path exists) {
        "./meso-forge-tooling"
    } else {
        print $"(ansi red)Error: meso-forge-tooling not found. Please ensure it's installed or set MESO_FORGE_TOOLING_ROOT(ansi reset)"
        exit 1
    }
}

# Helper function to run nushell scripts
def run_nu_script [
    scripts_dir: string
    script_name: string
    script_args: list<string>
] {
    let script_path = $scripts_dir | path join $script_name

    if not ($script_path | path exists) {
        print $"(ansi red)Error: Script not found: ($script_path)(ansi reset)"
        exit 1
    }

    nu $script_path ...$script_args
}

# Helper function to run Python scripts
def run_py_script [
    scripts_dir: string
    script_name: string
    script_args: list<string>
] {
    let script_path = $scripts_dir | path join $script_name

    if not ($script_path | path exists) {
        print $"(ansi red)Error: Script not found: ($script_path)(ansi reset)"
        exit 1
    }

    python $script_path ...$script_args
}

# Helper function to list local packages
def list_local_packages [] {
    if ("./pkgs" | path exists) {
        ls "./pkgs" | get name | each { |pkg| $pkg | path basename } | sort
    } else {
        print "No packages directory found"
        []
    }
}

# Helper function to list available skeletons
def list_skeletons [skeletons_dir: string] {
    if ($skeletons_dir | path exists) {
        let skeletons = ls $skeletons_dir
            | get name
            | each { |skeleton| $skeleton | path basename }
            | where ($it | str starts-with '_skeleton_')
            | each { |skeleton| $skeleton | str replace '_skeleton_' '' }

        if ($skeletons | length) > 0 {
            $skeletons | each { |skeleton| print $"  ($skeleton)" } | ignore
        } else {
            print "  No skeletons found"
        }
    } else {
        print "No skeletons directory found"
    }
}

# Helper function to list nushell scripts
def list_nu_scripts [scripts_dir: string] {
    if ($scripts_dir | path exists) {
        try {
            let scripts = ls $scripts_dir
                | where name =~ '\.nu$'
                | get name
                | each { |script| $script | path basename | str replace '\.nu$' '' }

            if ($scripts | length) > 0 {
                $scripts | each { |script| print $"  ($script)" } | ignore
            } else {
                print "  No .nu scripts found"
            }
        } catch {
            print "  No .nu scripts found"
        }
    } else {
        print "  No scripts directory found"
    }
}

# Helper function to list Python scripts
def list_py_scripts [scripts_dir: string] {
    if ($scripts_dir | path exists) {
        try {
            let scripts = ls $scripts_dir
                | where name =~ '\.py$'
                | where name !~ '__pycache__|__init__'
                | get name
                | each { |script| $script | path basename | str replace '\.py$' '' }

            if ($scripts | length) > 0 {
                $scripts | each { |script| print $"  ($script)" } | ignore
            } else {
                print "  No .py scripts found"
            }
        } catch {
            print "  No .py scripts found"
        }
    } else {
        print "  No scripts directory found"
    }
}

# Helper function to show configuration
def show_config [tooling_root: string, scripts_dir: string, skeletons_dir: string] {
    print "Meso-forge tooling configuration:"
    print $"  Tooling root: ($tooling_root)"
    print $"  Scripts dir:  ($scripts_dir)"
    print $"  Skeletons:    ($skeletons_dir)"
    print $"  Working dir:  (pwd)"
    print $"  Version:      ($env.MESO_FORGE_VERSION? | default 'unknown')"
    print ""

    let packages = list_local_packages
    if ($packages | length) > 0 {
        print $"Local packages (($packages | length)):"
        $packages | each { |pkg| print $"  ($pkg)" } | ignore
    } else {
        print "No local packages directory found"
    }
}

# Helper function to show comprehensive help
def show_help [tooling_root: string] {
    print "meso-forge - Multi-package build suite"
    print ""
    print "USAGE:"
    print "    meso-forge <command> [options]"
    print ""
    print "BUILD COMMANDS:"
    print "    build <package>         Build a specific package"
    print "    build-all              Build all packages"
    print "    build-noarch           Build noarch packages only"
    print "    build-platform         Build platform-specific packages"
    print "    build-single --recipe <path>  Build from specific recipe file"
    print ""
    print "PUBLISHING COMMANDS:"
    print "    publish                Publish built packages (interactive mode selection)"
    print "    publish-pd             Publish to prefix.dev"
    print "    publish-s3             Publish to S3"
    print "    publish-local          Publish to local MinIO (localhost:19000)"
    print ""
    print "TESTING COMMANDS:"
    print "    test                   Test all built packages"
    print "    test-package <name>    Test a specific package"
    print ""
    print "PACKAGE MANAGEMENT:"
    print "    check <package>        Check if package exists in repositories"
    print "    retract                Retract packages from repositories"
    print "    init-package <type> <name>  Create new package from skeleton"
    print "    list-packages          List available local packages"
    print "    list-skeletons         List available package skeletons"
    print ""
    print "QUALITY ASSURANCE:"
    print "    lint                   Lint recipe files"
    print "    analyze                Analyze recipes for issues"
    print "    generate-readmes       Generate README files for packages"
    print ""
    print "VERSION CONTROL:"
    print "    version-update         Update package versions from upstream"
    print "    test-plugins           Test version control plugins"
    print ""
    print "UTILITY COMMANDS:"
    print "    list-scripts           List all available scripts"
    print "    config                 Show configuration and environment info"
    print "    help                   Show this help"
    print ""
    print "PACKAGE SKELETONS:"
    print "    _skeleton_python       Python package"
    print "    _skeleton_rust         Rust package"
    print "    _skeleton_cxx_appl     C++ application"
    print "    _skeleton_cxx_hdr      C++ header-only library"
    print "    _skeleton_cxx_meson    C++ with Meson build"
    print "    _skeleton_go           Go package"
    print "    _skeleton_js           JavaScript/Node.js package"
    print "    _skeleton_jvm          JVM-based package"
    print "    _skeleton_rlang        R language package"
    print "    _skeleton_ruby         Ruby package"
    print ""
    print "EXAMPLES:"
    print "    # Package development workflow"
    print "    meso-forge init-package _skeleton_python my-tool"
    print "    meso-forge build my-tool"
    print "    meso-forge test-package my-tool"
    print "    meso-forge publish-pd"
    print ""
    print "    # Bulk operations"
    print "    meso-forge build-all"
    print "    meso-forge lint"
    print "    meso-forge version-update"
    print ""
    print "    # Repository management"
    print "    meso-forge check numpy"
    print "    meso-forge list-packages"
    print "    meso-forge config"
    print ""
    print "ENVIRONMENT:"
    print "    Set MESO_FORGE_TOOLING_ROOT to override tooling location"
    print "    Default locations checked:"
    print "    1. $MESO_FORGE_TOOLING_ROOT (if set)"
    print "    2. $CONDA_PREFIX/share/meso-forge-tooling"
    print "    3. ./meso-forge-tooling"
    print ""
    print "For detailed documentation, see:"
    print $"    ($tooling_root)/README.adoc"
    print $"    ($tooling_root)/docs/"
}
