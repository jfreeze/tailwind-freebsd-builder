Build TailwindCSS CLI v3 for FreeBSD.

## Usage

This project contains the build scripts to create a standalone `tailwindcss` executable. It is only compatible with `Amd64` FreeBSD systems.

Run the following script from a FreeBSD host to build the TailwindCSS CLI binaries.

```shell
git clone https://github.com/jfreeze/tailwind-freebsd-builder.git
cd tailwind-freebsd-builder
cd src/v3

# if not building 3.4.17 set the version, e.g. 3.4.13
export TAILWIND_VSN=3.4.13

./setup-tailwind-build.sh
./build-tailwindcss.sh -v -k -c
```

Note: This script will take hours to compile and needs additional swap to run. It has been successfully run with 10GB of additional swap.

## Comments on TailwindCSS v4

TailwindCSS v4 is a major release that has a number of changes that are not compatible with the current build scripts. 

After going down several rabbit holes, I think the best option is to wait for `bun` to be compiled on FreeBSD.
Currently `bun` is not supported on the BSDs.

The work around is to use the Node version of `tailwindcss` for v4. Using this hybrid approach with `esbuild` is simple to setup and use. Using the hybrid approach comes with the added bonus that TailwindCSS v4 can be used on Arm64 architectures.

For details on how to use TailwindCSS v4 with Phoenix, see the online documentation for the [Horizon project](https://hex.pm/packages/horizon).

## Release

Download a binary releases directly.

- [tailwindcss-freebsd-x64 3.4.13](https://github.com/jfreeze/tailwind-freebsd-builder/releases/download/3.4.13/tailwindcss-freebsd-x64)
- [tailwindcss-freebsd-x64 3.4.17](https://github.com/jfreeze/tailwind-freebsd-builder/releases/download/3.4.17/tailwindcss-freebsd-x64)