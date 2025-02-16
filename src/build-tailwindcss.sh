#!/bin/sh
#
# build-tailwind.sh - Build script for TailwindCSS on FreeBSD
#

set -e

# Load shared configuration
script_dir=$(dirname "$(realpath "$0")")
. "${script_dir}/config.sh"

# Create build root if it doesn't exist
mkdir -p "${BUILD_ROOT}/${TAILWIND_VSN}/bin"

# Logging functions
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
}

log_debug() {
    if [ "${VERBOSE}" -eq 1 ]; then
        echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') $1"
    fi
}

# Error handling
check_exit() {
    local exit_code=$?
    local context="$1"
    if [ ${exit_code} -ne 0 ]; then
        log_error "${context} failed with exit code ${exit_code}"
        if [ -f "${NODE_BUILD_DIR}/logs/error.log" ]; then
            log_error "Build error log:"
            cat "${NODE_BUILD_DIR}/logs/error.log"
        fi
        exit ${exit_code}
    fi
}

# Cleanup function
cleanup() {
    if [ "${KEEP_TMPDIR}" -eq 1 ]; then
        log_debug "Keeping temporary directory: ${TMPDIR}"
        return
    fi

    if [ -n "${NODE_BUILD_DIR}" ] && [ -d "${NODE_BUILD_DIR}/logs" ]; then
        log_debug "Cleaning up logs in: ${NODE_BUILD_DIR}/logs"
        rm -rf "${NODE_BUILD_DIR}/logs"
    fi

    if [ -n "${TMPDIR}" ] && [ -d "${TMPDIR}" ]; then
        log_debug "Cleaning up ${TMPDIR}"
        rm -rf "${TMPDIR}"
    fi
}

# Setup Rust toolchain
setup_rust() {
    log_info "Setting up Rust toolchain..."
    if command -v rustup >/dev/null 2>&1; then
        log_info "Updating existing Rust installation..."
        rustup update
    else
        log_info "Installing Rust..."
        fetch https://sh.rustup.rs -o rustup-init.sh
        sh rustup-init.sh -y --no-modify-path
        rm rustup-init.sh
    fi
    check_exit "Rust setup"

    # Add Rust to PATH if needed
    if [ -f "$HOME/.cargo/env" ]; then
        . "$HOME/.cargo/env"
    fi
}

# Options
VERBOSE=0
DRY_RUN=0
CLEAN_BUILD=0
KEEP_TMPDIR=0
: "${PARALLEL_JOBS:=8}"

# Parse command line options
while getopts "vdckj:" opt; do
    case "${opt}" in
        v) VERBOSE=1 ;;
        d) DRY_RUN=1 ;;
        c) CLEAN_BUILD=1 ;;
        k) KEEP_TMPDIR=1 ;;
        j) PARALLEL_JOBS="${OPTARG}" ;;
        *) echo "Usage: $0 [-v] [-d] [-c] [-k] [-j jobs]
    -v: Verbose output
    -d: Dry run (don't actually build)
    -c: Clean build (remove existing build artifacts)
    -k: Keep temporary directory (don't clean up)
    -j: Number of parallel jobs (default: 8)" >&2; exit 1 ;;
    esac
done

# Setup environment
setup_environment() {
    # Build directories
    TAILWIND_BUILD="${BUILD_ROOT}/${TAILWIND_VSN}"
    if [ "${CLEAN_BUILD}" -eq 1 ]; then
        log_debug "Cleaning build directory: ${TAILWIND_BUILD}"
        rm -rf "${TAILWIND_BUILD}"
    fi
    mkdir -p "${TAILWIND_BUILD}/bin"

    : "${TMPDIR:=$(mktemp -d -t tailwind)}"
    cd "${TMPDIR}" || {
        log_error "Cannot enter temp directory: ${TMPDIR}"
        exit 1
    }
    TAILWIND_SRC="${TMPDIR}/src"

    # Set up build flags
    eval "$(get_build_flags)"
    eval "$(get_system_paths)"

    # Add node_modules/.bin to PATH
    export PATH="${TMPDIR}/node_modules/.bin:${PATH}"

    log_debug "Working directory: $(pwd)"
    log_debug "Build directory: ${TMPDIR}"
    log_debug "Cache directory: ${TAILWIND_BUILD}"
    log_debug "Compiler: ${CC}"
    log_debug "Make flags: ${MAKEFLAGS}"
}

# Clone source
clone_source() {
    log_info "Cloning Tailwind CSS v${TAILWIND_VSN}..."
    
    git clone --branch "v${TAILWIND_VSN}" --depth 1 \
        https://github.com/tailwindlabs/tailwindcss.git "${TAILWIND_SRC}"
    check_exit "Source clone"

    cd "${TAILWIND_SRC}"
    
    # Verify commit hash
    ACTUAL_COMMIT=$(git rev-parse HEAD)
    if [ "${TAILWIND_COMMIT}" != "${ACTUAL_COMMIT}" ]; then
        log_error "Commit hash mismatch"
        log_error "Expected: ${TAILWIND_COMMIT}"
        log_error "Got: ${ACTUAL_COMMIT}"
        exit 1
    fi
    log_debug "Verified commit hash: ${ACTUAL_COMMIT}"
}

# Setup workspace
setup_workspace() {
    cd "${TAILWIND_SRC}" || exit 1
    
    # Create all required directories
    mkdir -p crates/standalone/src
    mkdir -p crates/standalone/css

    log_debug "Creating directory structure..."
    log_debug "pwd: $(pwd)"
    log_debug "Standalone path: $(pwd)/crates/standalone"
    ls -la crates/standalone
    
    log_debug "Copying CSS files..."
    
    # Copy core CSS files
    for file in index preflight theme utilities; do
        if [ -f "packages/tailwindcss/${file}.css" ]; then
            cp "packages/tailwindcss/${file}.css" "crates/standalone/css/"
            log_debug "Copied ${file}.css"
        else
            log_error "Missing ${file}.css"
            ls -la "packages/tailwindcss/${file}.css" || true
        fi
    done

    log_debug "CSS directory contents:"
    ls -la crates/standalone/css/
    
    # Create Cargo.toml for standalone binary
    cat > crates/standalone/Cargo.toml << 'EOF'
[package]
name = "tailwindcss"
version = "4.0.6"
edition = "2021"

[dependencies]
tailwindcss-oxide = { path = "../oxide" }
clap = { version = "4.4.18", features = ["derive"] }
anyhow = "1.0.79"
notify = "6.1.1"
tokio = { version = "1.36.0", features = ["full"] }
rust-embed = { version = "8.0.0", features = ["include-exclude"] }
EOF

    # Create main.rs for standalone binary
    log_debug "Creating main.rs..."
    cat > crates/standalone/src/main.rs << 'EOF'
use anyhow::{Context, Result};
use clap::Parser;
use notify::{RecursiveMode, Watcher};
use rust_embed::RustEmbed;
use std::path::PathBuf;
use std::sync::mpsc::channel;
use tailwindcss_oxide::Scanner;

#[derive(RustEmbed)]
#[folder = "css"]
struct Asset;

#[derive(Parser, Debug)]
#[command(version)]
struct Args {
    /// Input file
    #[arg(short, long)]
    input: PathBuf,

    /// Output file
    #[arg(short, long)]
    output: PathBuf,

    /// Watch for changes
    #[arg(short, long)]
    watch: bool,
}

fn get_embedded_css(name: &str) -> Option<String> {
    Asset::get(&format!("{}.css", name))
        .map(|f| String::from_utf8_lossy(&f.data).into_owned())
}

async fn process_file(input: &PathBuf, output: &PathBuf) -> Result<()> {
    // Read input file
    let css = std::fs::read_to_string(input)
        .with_context(|| format!("Failed to read input file: {}", input.display()))?;

    // Create scanner
    let mut scanner = Scanner::new(None);
    let candidates = scanner.scan();

    // Get base CSS if needed
    let mut content = String::new();
    if let Some(base) = get_embedded_css("preflight") {
        content.push_str(&base);
        content.push('\n');
    }
    content.push_str(&css);

    // Write output
    std::fs::write(output, content)
        .with_context(|| format!("Failed to write output file: {}", output.display()))?;

    println!("Generated {} from {}", output.display(), input.display());
    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();

    // Process once initially
    process_file(&args.input, &args.output).await?;

    // Watch for changes if requested
    if args.watch {
        println!("Watching for changes...");
        let (tx, rx) = channel();

        let mut watcher = notify::recommended_watcher(move |res| {
            tx.send(res).unwrap();
        })?;

        watcher.watch(&args.input, RecursiveMode::NonRecursive)?;

        for res in rx {
            match res {
                Ok(_) => {
                    if let Err(e) = process_file(&args.input, &args.output).await {
                        eprintln!("Error: {}", e);
                    }
                }
                Err(e) => eprintln!("Watch error: {}", e),
            }
        }
    }

    Ok(())
}
EOF

    log_debug "Creating workspace Cargo.toml..."
    # Add standalone to workspace
    cat > Cargo.toml << 'EOF'
[workspace]
resolver = "2"
members = [
    "crates/node",
    "crates/oxide",
    "crates/standalone"
]

[profile.release]
lto = true
codegen-units = 1
opt-level = 3
EOF

    # Install dependencies
    log_debug "Installing workspace dependencies..."
    PNPM_HOME="${TMPDIR}/.pnpm" pnpm install --no-lockfile --ignore-scripts
    check_exit "Workspace dependencies installation"
}

# Build standalone CLI
build_standalone() {
    cd "${TAILWIND_SRC}/crates/standalone" || {
        log_error "Cannot find standalone directory"
        exit 1
    }

    log_debug "Building standalone CLI from: $(pwd)"

    # Build binary
    log_debug "Building standalone binary..."
    mkdir -p "${TAILWIND_BUILD}/target"
    
    CARGO_TARGET_DIR="${TAILWIND_BUILD}/target" \
    RUSTFLAGS="-C target-cpu=native" \
        cargo build --release
    check_exit "Standalone binary build"

    log_debug "Locating built binary..."
    find "${TAILWIND_BUILD}/target" -name tailwindcss -type f -ls

    # Copy binary if found
    binary_path="${TAILWIND_BUILD}/target/release/tailwindcss"
    if [ -f "${binary_path}" ]; then
        cp "${binary_path}" "${TAILWIND_BUILD}/bin/"
        chmod 755 "${TAILWIND_BUILD}/bin/tailwindcss"
        check_exit "Binary installation"
    else
        log_error "Could not find built binary at: ${binary_path}"
        exit 1
    fi

    # Create wrapper script
    cat > "${TAILWIND_BUILD}/bin/tailwind" << EOF
#!/bin/sh
NODE_OPTIONS="--no-warnings" exec "${TAILWIND_BUILD}/bin/tailwindcss" "\$@"
EOF
    chmod 755 "${TAILWIND_BUILD}/bin/tailwind"
}

# Main
main() {
    log_info "Starting Tailwind CSS build process v${SCRIPT_VERSION}"

    trap cleanup EXIT

    setup_environment
    setup_rust
    clone_source
    setup_workspace
    build_standalone

    log_info "Build completed successfully"
    log_info "Binary installed to: ${TAILWIND_BUILD}/bin/tailwindcss"
    log_info "Wrapper script installed to: ${TAILWIND_BUILD}/bin/tailwind"
}

main "$@"
