#!/bin/sh
#
# setup-tailwind-build.sh - Install dependencies for building TailwindCSS on FreeBSD
#

set -e

# Configuration
REQUIRED_PKGS="devel/binutils devel/gmake lang/gcc12 lang/python sysutils/patchelf devel/git@tiny www/npm-node18 patchelf perl5 python310"

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

# Install packages
echo "Installing required packages..."
doas pkg install -yr FreeBSD ${REQUIRED_PKGS}

# Verify installation
echo "Verifying installation..."
missing_deps=0
for cmd in gcc12 gmake git npm python3.10 patchelf perl; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "Error: ${cmd} is still not available after installation"
        missing_deps=1
    fi
done

if [ "${missing_deps}" -eq 1 ]; then
    echo "Some dependencies failed to install properly"
    exit 1
fi

echo "Setup completed successfully"
echo "You can now run build-tailwindcss.sh to build TailwindCSS"
