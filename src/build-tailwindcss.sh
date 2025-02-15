#!/bin/sh
#
# build-tailwind.sh - Build script for TailwindCSS on FreeBSD
#
# Usage: ./build-tailwind.sh [-v] [-d] [-c] [-k] [-j jobs]
#   -v: Verbose output
#   -d: Dry run (don't actually build)
#   -c: Clean build (remove existing build artifacts)
#   -k: Keep temporary directory (don't clean up)
#   -j: Number of parallel jobs (default: 8)
#

set -e

# Configuration
readonly SCRIPT_VERSION="1.0.0"
readonly TAILWIND_VSN="${TAILWIND_VSN:-4.0.6}"
readonly PARALLEL_JOBS="${PARALLEL_JOBS:-8}"
readonly GCC_VERSION="12"
readonly BUILD_ROOT="${HOME}/.cache/tailwind-build"

# Options
VERBOSE=0
DRY_RUN=0
CLEAN_BUILD=0
KEEP_TMPDIR=0

# Create build root if it doesn't exist
mkdir -p "${BUILD_ROOT}"

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
    if [ "${KEEP_TMPDIR}" -eq 1 ]; then
        log_debug "Keeping temporary directory: ${TMPDIR}"
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
    
    for cmd in gcc${GCC_VERSION} gmake git pnpm python3.10 patchelf perl node; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            log_error "${cmd} is required but not installed"
            missing_deps=1
        fi
    done
    
    if [ "${missing_deps}" -eq 1 ]; then
        echo "Please run setup-tailwind-build.sh first to install dependencies"
        exit 1
    fi
}

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
    # System paths
    : "${CC:=/usr/local/bin/gcc${GCC_VERSION}}"
    : "${CXX:=/usr/local/bin/g++${GCC_VERSION}}"
    : "${LD:=/usr/local/bin/ld}"
    : "${MAKE:=/usr/local/bin/gmake}"
    
    # Build configuration
    : "${MAKEFLAGS:=-j${PARALLEL_JOBS}}"
    : "${LDFLAGS:=-Wl,-rpath=/usr/local/lib/gcc${GCC_VERSION}}"
    
    # Build directories
    TAILWIND_BUILD="${BUILD_ROOT}/${TAILWIND_VSN}"
    if [ "${CLEAN_BUILD}" -eq 1 ]; then
        log_debug "Cleaning build directory: ${TAILWIND_BUILD}"
        rm -rf "${TAILWIND_BUILD}"
    fi
    mkdir -p "${TAILWIND_BUILD}"

    : "${TMPDIR:=$(mktemp -d -t tailwind)}"
    : "${TAILWIND:=${TMPDIR}/src}"
    
    export CC CXX LD MAKE MAKEFLAGS LDFLAGS TMPDIR TAILWIND TAILWIND_BUILD
    export PATH="${TMPDIR}:${PATH}"
    
    log_debug "Build directory: ${TMPDIR}"
    log_debug "Cache directory: ${TAILWIND_BUILD}"
    log_debug "Compiler: ${CC}"
    log_debug "Make flags: ${MAKEFLAGS}"
}

# Clone source
clone_source() {
    log_info "Cloning Tailwind CSS v${TAILWIND_VSN}..."
    if [ "${DRY_RUN}" -eq 0 ]; then
        git clone --branch "v${TAILWIND_VSN}" --depth 1 \
            https://github.com/tailwindlabs/tailwindcss.git "${TAILWIND}"
        check_exit "Source clone"
        
        log_debug "Cloned into ${TAILWIND}"
        log_debug "Contents of clone directory:"
        ls -la "${TAILWIND}"
    fi
}

# Build process
build_tailwind() {
    if [ "${DRY_RUN}" -eq 1 ]; then
        return
    fi
    
    log_info "Building Tailwind CSS..."
    
    # Install base dependencies first
    cd "${TAILWIND}"
    log_debug "Installing main dependencies..."
    log_debug "Current directory: $(pwd)"
    
    # Create minimal base package.json
    cat > package.json << 'EOF'
{
  "name": "tailwindcss-build",
  "private": true,
  "version": "4.0.6",
  "dependencies": {
    "tailwindcss": "4.0.6",
    "postcss": "^8.4.35",
    "autoprefixer": "^10.4.17"
  }
}
EOF
    
    PNPM_HOME="${TMPDIR}/.pnpm" pnpm install --no-frozen-lockfile --ignore-scripts
    check_exit "Base dependencies install"
    
    # Move to standalone directory
    STANDALONE_DIR="packages/@tailwindcss-standalone"
    if [ ! -d "${STANDALONE_DIR}" ]; then
        log_error "Could not find ${STANDALONE_DIR}"
        exit 1
    fi
    
    cd "${STANDALONE_DIR}"
    log_debug "Now in standalone directory: $(pwd)"
    log_debug "Directory contents:"
    ls -la
    
    log_debug "Original package.json contents:"
    cat package.json
    
    # Create build directory
    mkdir -p dist
    
    # Install build dependencies
    cat > package.json << 'EOF'
{
  "name": "@tailwindcss/standalone",
  "private": true,
  "version": "4.0.6",
  "dependencies": {
    "tailwindcss": "4.0.6",
    "@tailwindcss/typography": "^0.5.10",
    "@tailwindcss/forms": "^0.5.7",
    "@tailwindcss/aspect-ratio": "^0.4.2",
    "@tailwindcss/container-queries": "^0.1.1",
    "postcss": "^8.4.35",
    "autoprefixer": "^10.4.17",
    "pkg": "^5.8.1",
    "typescript": "^5.3.3"
  },
  "bin": "dist/index.js",
  "pkg": {
    "scripts": "dist/index.js",
    "targets": ["node18-freebsd-x64"],
    "outputPath": "dist"
  }
}
EOF
    
    PNPM_HOME="${TMPDIR}/.pnpm" pnpm install --no-frozen-lockfile --ignore-scripts
    check_exit "Standalone dependencies install"
    
    # Navigate to the correct directory
    cd "${TAILWIND}"
    log_debug "Current working directory: $(pwd)"
    log_debug "Directory contents:"
    ls -la

    # Install root dependencies first
    log_debug "Installing root dependencies..."
    cd "${TAILWIND}"
    PNPM_HOME="${TMPDIR}/.pnpm" pnpm install --no-frozen-lockfile
    check_exit "Root dependencies install"
    
    # Setup Rust toolchain
    log_debug "Setting up Rust toolchain..."
    if command -v rustup >/dev/null 2>&1; then
        log_debug "Rustup found, updating..."
        rustup update
    else
        log_debug "Installing Rustup..."
        fetch https://sh.rustup.rs -o rustup-init.sh
        sh rustup-init.sh -y --no-modify-path
        export PATH="$HOME/.cargo/bin:$PATH"
    fi
    check_exit "Rust setup"
    
    # Build Rust components if needed
    log_debug "Building Rust components..."
    . "$HOME/.cargo/env"
    if [ ! -f "${TAILWIND_BUILD}/target/release/libtailwindcss_oxide.a" ] || [ "${CLEAN_BUILD}" -eq 1 ]; then
        log_debug "Building Rust from source..."
        cd "${TAILWIND}"
        cargo build --release --target-dir="${TAILWIND_BUILD}/target"
        check_exit "Rust build"
    else
        log_debug "Using cached Rust build"
    fi
    
    # Build Node components directly
    cd packages/@tailwindcss-node
    log_debug "Building @tailwindcss/node..."
    PNPM_HOME="${TMPDIR}/.pnpm" pnpm install --no-frozen-lockfile
    PNPM_HOME="${TMPDIR}/.pnpm" pnpm run build
    check_exit "@tailwindcss/node build"
    
    # Build oxide components
    cd ../oxide
    log_debug "Building @tailwindcss/oxide..."
    PNPM_HOME="${TMPDIR}/.pnpm" pnpm install --no-frozen-lockfile
    PNPM_HOME="${TMPDIR}/.pnpm" pnpm run build
    check_exit "@tailwindcss/oxide build"
    
    # Finally build standalone
    cd ../standalone
    log_debug "Building standalone CLI..."
    PNPM_HOME="${TMPDIR}/.pnpm" pnpm install --no-frozen-lockfile
    
    log_debug "Creating build script..."
    mkdir -p scripts
    cat > scripts/build.js << 'EOF'
import esbuild from 'esbuild';
import path from 'path';

try {
  await esbuild.build({
    entryPoints: ['src/index.ts'],
    bundle: true,
    platform: 'node',
    target: ['node18'],
    outfile: 'dist/index.mjs',
    format: 'esm',
    external: [
      'node:*',
      '@tailwindcss/node',
      '@tailwindcss/oxide',
      'tailwindcss',
      '@tailwindcss/typography',
      '@tailwindcss/forms',
      '@tailwindcss/aspect-ratio',
      '@tailwindcss/container-queries'
    ],
  });
  console.log('Build completed successfully');
} catch (error) {
  console.error('Build failed:', error);
  process.exit(1);
}
EOF
    
    # Run build
    mkdir -p dist
    PNPM_HOME="${TMPDIR}/.pnpm" node scripts/build.js
    check_exit "Standalone build"

    # Now navigate to standalone
    CLI_DIR="packages/@tailwindcss-standalone"
    log_debug "Changing to ${CLI_DIR}"
    cd "${CLI_DIR}"
    
    log_debug "Current directory: $(pwd)"
    log_debug "Directory contents:"
    ls -la

    # Create package.json with correct dependencies
    log_debug "Creating package.json..."
    mv package.json package.json.orig
    cat > package.json << 'EOF'
{
  "name": "@tailwindcss/standalone",
  "version": "4.0.6",
  "private": true,
  "type": "module",
  "bin": {
    "tailwindcss": "./dist/index.mjs"
  },
  "dependencies": {
    "@tailwindcss/node": "workspace:*",
    "@tailwindcss/oxide": "workspace:*",
    "@tailwindcss/aspect-ratio": "^0.4.2",
    "@tailwindcss/forms": "^0.5.10",
    "@tailwindcss/typography": "^0.5.16",
    "@tailwindcss/container-queries": "^0.1.1",
    "tailwindcss": "4.0.6",
    "postcss": "^8.4.35",
    "autoprefixer": "^10.4.17"
  },
  "devDependencies": {
    "@types/node": "^20.11.19",
    "esbuild": "^0.19.12",
    "typescript": "^5.3.3"
  }
}
EOF

    # Create tsconfig.json
    log_debug "Creating tsconfig.json..."
    cat > tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "node",
    "esModuleInterop": true,
    "resolveJsonModule": true,
    "allowJs": true,
    "checkJs": false,
    "noEmit": true,
    "isolatedModules": true,
    "forceConsistentCasingInFileNames": true,
    "strict": true,
    "skipLibCheck": true,
    "types": ["node"]
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules"]
}
EOF

    # Create build script
    log_debug "Creating build script..."
    mkdir -p scripts
    cat > scripts/build.js << 'EOF'
import { build } from 'esbuild';
import path from 'path';

try {
  await build({
    entryPoints: ['src/index.ts'],
    bundle: true,
    platform: 'node',
    target: ['node18'],
    outfile: 'dist/index.mjs',
    format: 'esm',
    external: [
      'node:*',
      '@tailwindcss/node',
      '@tailwindcss/oxide',
      'tailwindcss',
      '@tailwindcss/typography',
      '@tailwindcss/forms',
      '@tailwindcss/aspect-ratio',
      '@tailwindcss/container-queries'
    ],
  });
  console.log('Build completed successfully');
} catch (error) {
  console.error('Build failed:', error);
  process.exit(1);
}
EOF

    # Install dependencies
    log_debug "Installing dependencies..."
    PNPM_HOME="${TMPDIR}/.pnpm" pnpm install --no-frozen-lockfile
    check_exit "Dependencies install"

    # Build
    log_debug "Building TypeScript source..."
    mkdir -p dist
    PNPM_HOME="${TMPDIR}/.pnpm" pnpm run build
    check_exit "Build"

    # Create package.json
    log_debug "Creating package.json..."
    mv package.json package.json.orig
    cat > package.json << 'EOF'
{
  "name": "@tailwindcss/standalone",
  "version": "4.0.6",
  "private": true,
  "type": "module",
  "bin": {
    "tailwindcss": "./dist/index.mjs"
  },
  "scripts": {
    "build": "node scripts/build.js"
  },
  "dependencies": {
    "@tailwindcss/aspect-ratio": "^0.4.2",
    "@tailwindcss/forms": "^0.5.10",
    "@tailwindcss/typography": "^0.5.16",
    "@tailwindcss/container-queries": "^0.1.1",
    "tailwindcss": "4.0.6",
    "postcss": "^8.4.35",
    "autoprefixer": "^10.4.17"
  },
  "devDependencies": {
    "@types/node": "^20.11.19",
    "esbuild": "^0.19.12",
    "typescript": "^5.3.3"
  }
}
EOF

    # Create build script
    log_debug "Creating build script..."
    mkdir -p scripts
    cat > scripts/build.js << 'EOF'
import { build } from 'esbuild';
import path from 'path';

try {
  await build({
    entryPoints: ['src/index.ts'],
    bundle: true,
    platform: 'node',
    target: ['node18'],
    outfile: 'dist/index.mjs',
    format: 'esm',
    external: [
      'node:*',
      '@tailwindcss/cli',
      'tailwindcss',
      '@tailwindcss/typography',
      '@tailwindcss/forms',
      '@tailwindcss/aspect-ratio',
      '@tailwindcss/container-queries'
    ],
  });
  console.log('Build completed successfully');
} catch (error) {
  console.error('Build failed:', error);
  process.exit(1);
}
EOF

    # Create tsconfig.json
    log_debug "Creating tsconfig.json..."
    cat > tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "node",
    "esModuleInterop": true,
    "resolveJsonModule": true,
    "allowJs": true,
    "checkJs": false,
    "noEmit": true,
    "isolatedModules": true,
    "forceConsistentCasingInFileNames": true,
    "strict": true,
    "skipLibCheck": true,
    "types": ["node"]
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules"]
}
EOF

    # Install dependencies
    log_debug "Installing dependencies..."
    PNPM_HOME="${TMPDIR}/.pnpm" pnpm install --no-frozen-lockfile
    check_exit "Dependencies install"

    # Build
    log_debug "Building TypeScript source..."
    mkdir -p dist
    PNPM_HOME="${TMPDIR}/.pnpm" pnpm run build
    check_exit "Build"
    
    # Build standalone binary
    log_debug "Building standalone binary..."
    ./node_modules/.bin/pkg \
        --targets node18-freebsd-x64 \
        --compress Brotli \
        --no-bytecode \
        --public-packages "*" \
        --output dist/tailwindcss-standalone \
        dist/index.js
    check_exit "Binary build"
    
    # Patch binary
    log_debug "Patching binary..."
    patchelf --add-rpath "/usr/local/lib/gcc${GCC_VERSION}" dist/tailwindcss-standalone
    check_exit "Binary patching"
    
    # Adjust payload position
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
    clone_source
    build_tailwind
    verify_build
    
    log_info "Build completed successfully"
}

main "$@"
