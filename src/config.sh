#!/bin/sh
#
# config.sh - Shared configuration for TailwindCSS build scripts
#

# Version information
readonly SCRIPT_VERSION="1.0.1"
readonly TAILWIND_VSN="${TAILWIND_VSN:-4.0.6}"
readonly TAILWIND_COMMIT="${TAILWIND_COMMIT:-d045aaa75edb8ee6b69c4b1e2551c2a844377927}"
readonly NODE_VSN="${NODE_VSN:-22}"
readonly GCC_VSN="${GCC_VSN:-12}"
readonly PNPM_VSN="${PNPM_VSN:-9.6.0}"
readonly TSUP_VSN="${TSUP_VSN:-8.0.2}"

# Path and directory configuration
readonly BUILD_ROOT="${HOME}/.cache/tailwind-build"

# Build directories will be:
# TAILWIND_SRC - temporary source directory
# TAILWIND_BUILD - cache directory for build artifacts
# These are set in the build script

# System paths
CC="${CC:-/usr/local/bin/gcc${GCC_VSN}}"
CXX="${CXX:-/usr/local/bin/g++${GCC_VSN}}"
LD="${LD:-/usr/local/bin/ld}"
MAKE="${MAKE:-/usr/local/bin/gmake}"
NODE_PATH="${NODE_PATH:-/usr/local/bin}"

export CC CXX LD MAKE NODE_PATH

# Required packages (for setup script)
readonly REQUIRED_PKGS="
    devel/gmake
    lang/gcc${GCC_VSN}
    lang/python310
    sysutils/patchelf
    devel/git@tiny
    www/node${NODE_VSN}
    perl5
    textproc/jq
"

# Required npm packages (global installs)
readonly REQUIRED_NPM_PKGS="
    pnpm@${PNPM_VSN}
    tsup@${TSUP_VSN}
"

# Build dependencies per component
readonly NODE_DEPS="
    typescript@5.3.3
    @types/node@20.11.19
    esbuild@0.19.12
    tsup@8.0.2
    @tailwindcss/oxide@4.0.6
    tailwindcss@4.0.6
"

readonly STANDALONE_DEPS="
    pkg@5.8.1
    typescript@5.3.3
    @types/node@20.11.19
    esbuild@0.19.12
"

# System paths
get_system_paths() {
    : "${CC:=/usr/local/bin/gcc${GCC_VSN}}"
    : "${CXX:=/usr/local/bin/g++${GCC_VSN}}"
    : "${LD:=/usr/local/bin/ld}"
    : "${MAKE:=/usr/local/bin/gmake}"
    : "${NODE_PATH:=/usr/local/bin}"
    echo "CC=${CC}"
    echo "CXX=${CXX}"
    echo "LD=${LD}"
    echo "MAKE=${MAKE}"
    echo "NODE_PATH=${NODE_PATH}"
}

# Build flags
get_build_flags() {
    : "${MAKEFLAGS:=-j${PARALLEL_JOBS}}"
    : "${LDFLAGS:=-Wl,-rpath=/usr/local/lib/gcc${GCC_VSN}}"
    echo "MAKEFLAGS=${MAKEFLAGS}"
    echo "LDFLAGS=${LDFLAGS}"
}

# Utility functions for version checking
version_gt() {
    test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

check_version() {
    local cmd="$1"
    local required="$2"
    local current
    current=$($cmd --version | head -n1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "0.0.0")
    if version_gt "$required" "$current"; then
        return 1
    fi
    return 0
}

# Export all readonly variables
export SCRIPT_VERSION TAILWIND_VSN NODE_VSN GCC_VSN PNPM_VSN TSUP_VSN
export PARALLEL_JOBS BUILD_ROOT REQUIRED_PKGS REQUIRED_NPM_PKGS
export NODE_DEPS STANDALONE_DEPS
