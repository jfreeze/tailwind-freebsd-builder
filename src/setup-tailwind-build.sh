#!/bin/sh
#
# setup-tailwind-build.sh - Install dependencies for building TailwindCSS on FreeBSD
#

set -e

# Load shared configuration
script_dir=$(dirname "$(realpath "$0")")
. "${script_dir}/config.sh"

# Logging functions
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
}

log_debug() {
    echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') $1"
}

# Error handling with context
check_cmd() {
    local exit_code=$?
    local context="$1"
    if [ ${exit_code} -ne 0 ]; then
        log_error "${context} failed with exit code ${exit_code}"
        exit ${exit_code}
    fi
}

# Check if running as root
check_root() {
    if [ "$(id -u)" -eq 0 ]; then
        log_error "This script should not be run as root"
        echo "Please run as a regular user with doas access"
        exit 1
    fi
}

# Check for doas access
check_doas() {
    if ! command -v doas >/dev/null 2>&1; then
        log_error "doas is required but not installed"
        cat << EOF
Please install doas first:
  $ su -
  # pkg install doas
  # echo 'permit :wheel' > /usr/local/etc/doas.conf
EOF
        exit 1
    fi
}

# Remove old Node.js packages
remove_old_node() {
    log_info "Checking for old Node.js packages..."
    for pkg in node18 npm-node18 node20 npm-node20; do
        if pkg info | grep -q "^${pkg}-"; then
            log_info "Removing ${pkg}..."
            doas pkg remove -y "${pkg}"
        fi
    done
}

# Install required system packages
install_system_packages() {
    log_info "Installing basic system packages..."
    doas pkg install -y textproc/jq
    check_cmd "jq installation"
    
    log_info "Installing required packages..."
    # shellcheck disable=SC2086
    doas pkg install -yr FreeBSD ${REQUIRED_PKGS}
    check_cmd "Package installation"

    # Install npm separately to ensure correct version
    log_info "Installing npm..."
    doas pkg install -y "www/npm-node${NODE_VSN}"
    check_cmd "NPM installation"
}

# Update PATH handling
update_path() {
    if ! echo "${PATH}" | grep -q "${NODE_PATH}"; then
        export PATH="${NODE_PATH}:${PATH}"
        
        # Update shell rc files
        for rc in ~/.profile ~/.shrc; do
            if [ -f "${rc}" ]; then
                if ! grep -q "PATH=.*${NODE_PATH}" "${rc}"; then
                    printf '\n# Node.js path\nexport PATH="%s:${PATH}"\n' "${NODE_PATH}" >> "${rc}"
                    log_info "Updated ${rc} with node path"
                fi
            fi
        done
    fi
}

# Verify tool versions
verify_versions() {
    log_info "Verifying installation..."
    local missing_deps=0

    # Check basic commands
    for cmd in "gcc${GCC_VSN}" gmake git npm "python3.10" patchelf perl node jq; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            log_error "${cmd} is still not available after installation"
            echo "Looking for ${cmd} in ${NODE_PATH}..."
            ls -l "${NODE_PATH}/${cmd}"* 2>/dev/null || true
            missing_deps=1
        fi
    done

    # Check Node.js version
    if ! check_version "node" "22.9.0"; then
        log_error "Node.js version must be 22.9.0 or later"
        missing_deps=1
    fi

    if [ "${missing_deps}" -eq 1 ]; then
        log_error "Some dependencies failed to install properly"
        echo "Current PATH: ${PATH}"
        echo "Please try logging out and back in, then run the script again"
        exit 1
    fi
}

# Install required npm packages
install_npm_packages() {
    log_info "Installing required npm packages..."
    # shellcheck disable=SC2086
    for pkg in ${REQUIRED_NPM_PKGS}; do
        log_info "Installing ${pkg}..."
        doas npm install -g "${pkg}"
        check_cmd "Installation of ${pkg}"
    done
}

# Setup Rust toolchain if needed
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
    check_cmd "Rust setup"

    # Add Rust to PATH if needed
    if [ -f "$HOME/.cargo/env" ]; then
        . "$HOME/.cargo/env"
    fi
}

# Create build directories
setup_directories() {
    log_info "Creating build directories..."
    mkdir -p "${BUILD_ROOT}"
    chmod 755 "${BUILD_ROOT}"
}

# Main
main() {
    log_info "Starting Tailwind CSS setup process v${SCRIPT_VERSION}"

    check_root
    check_doas
    remove_old_node
    install_system_packages
    update_path
    verify_versions
    install_npm_packages
    setup_rust
    setup_directories

    log_info "Setup completed successfully"
    cat << EOF

Environment is now ready for building TailwindCSS ${TAILWIND_VSN}
You may need to log out and back in for PATH changes to take effect

Current versions:
  Node.js: $(node --version)
  npm: $(npm --version)
  pnpm: $(pnpm --version)
  Rust: $(rustc --version)
  GCC: $(gcc${GCC_VSN} --version | head -n1)

Build cache directory: ${BUILD_ROOT}
EOF
}

main "$@"
