#!/bin/sh
#
# build-tailwindcss.sh - Build script for TailwindCSS on FreeBSD
#
# Usage: ./build-tailwind.sh [-v] [-d] [-c] [-j jobs]
#   -v: Verbose output
#   -d: Dry run (don't actually build)
#   -c: Clean build (remove existing build artifacts)
#   -j: Number of parallel jobs (default: 8)
#
# Dependencies:
#   - FreeBSD 13.0 or later
#   - devel/binutils
#   - devel/gmake
#   - lang/gcc12
#   - lang/python
#   - sysutils/patchelf
#   - devel/git@tiny
#   - www/npm-node18
#   - perl5
#   - python310

set -e

# Configuration
readonly SCRIPT_VERSION="1.0.0"
readonly TAILWIND_VSN="${TAILWIND_VSN:-4.0.6}"
readonly PARALLEL_JOBS="${PARALLEL_JOBS:-8}"
readonly GCC_VERSION="12"
readonly REQUIRED_PKGS="devel/binutils devel/gmake lang/gcc${GCC_VERSION} lang/python sysutils/patchelf devel/git@tiny www/npm-node18 patchelf perl5 python310"

# Options
VERBOSE=0
DRY_RUN=0
CLEAN_BUILD=0

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
    if [ $? -ne 0 ]; then
        log_error "$1 failed"
        exit 1
    fi
}

# Cleanup function
cleanup() {
    if [ "${DRY_RUN}" -eq 1 ]; then
        return
    fi
    
    if [ -n "${TMPDIR}" ] && [ -d "${TMPDIR}" ]; then
        log_debug "Cleaning up ${TMPDIR}"
        rm -rf "${TMPDIR}"
    fi
}

# Check for required commands
check_dependencies() {
    local missing_deps=0
    
    for cmd in gcc${GCC_VERSION} gmake git npm python3.10 patchelf perl; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            log_error "${cmd} is required but not installed"
            missing_deps=1
        fi
    done
    
    if [ "${missing_deps}" -eq 1 ]; then
        exit 1
    fi
}

# Parse command line options
while getopts "vdcj:" opt; do
    case "${opt}" in
        v) VERBOSE=1 ;;
        d) DRY_RUN=1 ;;
        c) CLEAN_BUILD=1 ;;
        j) PARALLEL_JOBS="${OPTARG}" ;;
        *) echo "Usage: $0 [-v] [-d] [-c] [-j jobs]" >&2; exit 1 ;;
    esac
done

# Setup environment
setup_environment() {
    # System paths
    : "${CC:=/usr/local/bin/gcc${GCC_VERSION}}"
    : "${CXX:=/usr/local/bin/g++${GCC_VERSION}}"
    : "${LD:=/usr/local/bin/ld}"
    : "${MAKE:=/usr/local/bin/gmake}"
    
    # Build configuration
    : "${MAKEFLAGS:=-j${PARALLEL_JOBS}}"
    : "${LDFLAGS:=-Wl,-rpath=/usr/local/lib/gcc${GCC_VERSION}}"
    
    # Build directories
    : "${TMPDIR:=$(mktemp -d -t tailwind)}"
    : "${TAILWIND:=${TMPDIR}/src}"
    
    # NPM configuration
    : "${NPM_CONFIG_CACHE:=${TMPDIR}/.npm}"
    : "${PKG_CACHE_PATH:=${TMPDIR}/.pkg-cache}"
    
    export CC CXX LD MAKE MAKEFLAGS LDFLAGS TMPDIR TAILWIND NPM_CONFIG_CACHE PKG_CACHE_PATH
    export PATH="${TMPDIR}:${PATH}"
    
    log_debug "Build directory: ${TMPDIR}"
    log_debug "Compiler: ${CC}"
    log_debug "Make flags: ${MAKEFLAGS}"
}

# Install dependencies
install_dependencies() {
    log_info "Installing required packages..."
    if [ "${DRY_RUN}" -eq 0 ]; then
        doas pkg install -yr FreeBSD ${REQUIRED_PKGS}
        check_exit "Package installation"
    fi
}

# Clone source
clone_source() {
    log_info "Cloning Tailwind CSS v${TAILWIND_VSN}..."
    if [ "${DRY_RUN}" -eq 0 ]; then
        git clone --branch "v${TAILWIND_VSN}" --depth 1 \
            https://github.com/tailwindlabs/tailwindcss.git "${TAILWIND}"
        check_exit "Source clone"
    fi
}

# Build process
build_tailwind() {
    if [ "${DRY_RUN}" -eq 1 ]; then
        return
    fi
    
    log_info "Building Tailwind CSS..."
    
    # Install dependencies
    cd "${TAILWIND}"
    log_debug "Installing main dependencies..."
    npm install --omit=dev
    check_exit "NPM install"
    
    # Build standalone CLI
    cd "./standalone-cli"
    log_debug "Installing CLI dependencies..."
    npm ci
    check_exit "NPM CI"
    
    log_debug "Installing Tailwind plugins..."
    npm install -D "tailwindcss@v${TAILWIND_VSN}" \
        @tailwindcss/typography@latest \
        @tailwindcss/forms@latest \
        @tailwindcss/aspect-ratio@latest \
        @tailwindcss/line-clamp@latest \
        postcss@latest \
        autoprefixer@latest
    check_exit "Plugin installation"
    
    log_debug "Building standalone binary..."
    ./node_modules/.bin/pkg . \
        --target "node18-freebsd-x64" \
        --compress Brotli \
        --no-bytecode \
        --public-packages "*" \
        --python /usr/local/bin/python3.10 \
        --public
    check_exit "Binary build"
    
    log_debug "Patching binary..."
    patchelf --add-rpath "/usr/local/lib/gcc${GCC_VERSION}" dist/tailwindcss-standalone
    check_exit "Binary patching"
    
    log_debug "Adjusting payload position..."
    perl -pe 's/(var PAYLOAD_POSITION = .)(\d+)/$1 . ($2 + 4096)/e; s/(var PRELUDE_POSITION = .)(\d+)/$1 . ($2 + 4096)/e;' \
        < dist/tailwindcss-standalone > "${HOME}/tailwindcss-freebsd-x64"
    check_exit "Payload adjustment"
    
    chmod +x "${HOME}/tailwindcss-freebsd-x64"
}

# Verify build
verify_build() {
    if [ "${DRY_RUN}" -eq 1 ]; then
        return
    fi
    
    log_info "Verifying build..."
    cd "${HOME}"
    
    if [ ! -x "./tailwindcss-freebsd-x64" ]; then
        log_error "Build verification failed: Binary not found or not executable"
        exit 1
    fi
    
    log_info "Generating checksums..."
    sha256 tailwindcss-freebsd-x64
    sha512 tailwindcss-freebsd-x64
}

# Main
main() {
    log_info "Starting Tailwind CSS build process v${SCRIPT_VERSION}"
    
    trap cleanup EXIT
    
    check_dependencies
    setup_environment
    install_dependencies
    clone_source
    build_tailwind
    verify_build
    
    log_info "Build completed successfully"
}

main "$@"
