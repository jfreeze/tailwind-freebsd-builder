Build CLI for TailwindCSS on FreeBSD.

## Usage

Run the following script from a FreeBSD host to build the TailwindCSS CLI binaries.

```shell
version=v3
TAILWIND_VSN=3.4.17

git clone git@github.com:jfreeze/tailwind-freebsd-builder.git
cd tailwind-freebsd-builder

cd src/${version}

./setup-tailwind-build.sh
./build-tailwindcss.sh -v -k -c
```

## Comments on TailwindCSS v4

TailwindCSS v4 is a major release that has a number of changes that are not compatible with the current build scripts. 

After going down several rabbit holes, I think the best option is to wait for `bun` to be compiled on FreeBSD.
Currently `bun` is not supported on the BSDs.

The work around is to use the Node version of `tailwindcss` for v4. Using this hybrid approach with `esbuild` 
 (with the added bonus that this) command to run the `bun` command on a Linux system.

```shell
It is a I will be working on a new version of the build scripts that will be compatible with TailwindCSS v4.

## Release

Download a binary releases directly.

- [tailwindcss-freebsd-x64 3.4.17](https://github.com/jfreeze/tailwind-freebsd-builder/releases/download/3.4.17/tailwindcss-freebsd-x64)