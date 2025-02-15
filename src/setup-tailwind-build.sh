#!/bin/sh
#
# setup-tailwind-build.sh - Install dependencies for building TailwindCSS on FreeBSD
#

set -e

# Configuration
REQUIRED_PKGS="devel/gmake \
    lang/gcc12 \
    lang/python310 \
    sysutils/patchelf \
    devel/git@tiny \
    www/node22 \
    perl5"

# Error handling
check_cmd() {
    if [ $? -ne 0 ]; then
        echo "Error: $1 failed"
        exit 1
    fi
}

# Check if running as root
if [ "$(id -u)" -eq 0 ]; then
    echo "This script should not be run as root"
    echo "Please run as a regular user with doas access"
    exit 1
fi

# Check for doas
if ! command -v doas >/dev/null 2>&1; then
    echo "doas is required but not installed"
    echo "Please install doas first:"
    echo "  $ su -"
    echo "  # pkg install doas"
    echo "  # echo 'permit :wheel' > /usr/local/etc/doas.conf"
    exit 1
fi

# Remove old Node.js packages if they exist
echo "Checking for old Node.js packages..."
for pkg in node18 npm-node18 node20 npm-node20 node22 npm-node22 npm; do
    if pkg info | grep -q "^${pkg}-"; then
        echo "Removing ${pkg}..."
        doas pkg remove -y "${pkg}"
    fi
done

# Install packages
echo "Installing required packages..."
doas pkg install -yr FreeBSD ${REQUIRED_PKGS}
check_cmd "Package installation"

# Install npm separately
echo "Installing npm..."
doas pkg install -y www/npm-node22
check_cmd "NPM installation"

# Update PATH if needed
NODE_PATH="/usr/local/bin"
if ! echo "${PATH}" | grep -q "${NODE_PATH}"; then
    export PATH="${NODE_PATH}:${PATH}"
    # Add to shell rc files if they exist
    for rc in ~/.profile ~/.shrc; do
        if [ -f "${rc}" ]; then
            if ! grep -q "PATH=.*${NODE_PATH}" "${rc}"; then
                echo "export PATH=\"${NODE_PATH}:\${PATH}\"" >> "${rc}"
                echo "Updated ${rc} with node path"
            fi
        fi
    done
fi

# Verify installation
echo "Verifying installation..."
missing_deps=0
for cmd in gcc12 gmake git npm python3.10 patchelf perl node; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "Error: ${cmd} is still not available after installation"
        echo "Looking for ${cmd} in ${NODE_PATH}..."
        ls -l "${NODE_PATH}/${cmd}"* 2>/dev/null || true
        missing_deps=1
    fi
done

if [ "${missing_deps}" -eq 1 ]; then
    echo "Some dependencies failed to install properly"
    echo "Current PATH: ${PATH}"
    echo "Please try logging out and back in, then run the script again"
    exit 1
fi

# Check Node.js version
NODE_VERSION=$(node --version)
echo "Node.js version: ${NODE_VERSION}"
if [ "$(printf '%s\n' "v22.9.0" "${NODE_VERSION}" | sort -V | head -n1)" = "v22.9.0" ]; then
    echo "Node.js version is compatible"
else
    echo "Error: Node.js version must be 22.9.0 or later"
    exit 1
fi

# Install pnpm
echo "Installing pnpm..."
doas npm install -g pnpm@9.6.0
check_cmd "PNPM installation"

# Check pnpm version
PNPM_VERSION=$(pnpm --version)
echo "pnpm version: ${PNPM_VERSION}"

echo "Setup completed successfully"
echo "You may need to log out and back in for PATH changes to take effect"
echo "Current PATH: ${PATH}"
echo "You can verify the installation with:"
echo "  node --version"
echo "  npm --version"
echo "  pnpm --version"
