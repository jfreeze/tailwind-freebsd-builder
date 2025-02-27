# TailwindCSS FreeBSD Builder

Build TailwindCSS CLI v3 for FreeBSD. Only compatible with `Amd64` architecture. The build process was originally created by [DCH](https://people.freebsd.org/~dch/).

## Usage with Phoenix

The pre-compiled binaries can be used with Phoenix Framework's built-in tasks:

```diff
+  @tailwindcss_freebsd_x64 "https://github.com/jfreeze/tailwind-freebsd-builder/releases/download/$version/tailwindcss-$target"

  ...
  defp aliases do
    [
      ...
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
+      "assets.setup.freebsd": [
+        "tailwind.install #{@tailwindcss_freebsd_x64}",
+        "esbuild.install --if-missing"
+      ],
      ...
    ]
  end
```

## Building from Source

Or run the following commands from a FreeBSD host to build the TailwindCSS CLI binaries:

```shell
git clone https://github.com/jfreeze/tailwind-freebsd-builder.git
cd tailwind-freebsd-builder
cd src/v3

# If not building 3.4.17, set the version
export TAILWIND_VSN=3.4.13

./setup-tailwind-build.sh
./build-tailwindcss.sh -v -k -c
```

**Note:** This compilation process takes several hours and requires about 10GB of additional swap space.

## TailwindCSS v4 Notes

TailwindCSS v4 is not compatible with the current build scripts. The recommended approach is to use the Node.js version of `tailwindcss` for v4 with `esbuild` until `bun` is available for FreeBSD.

For details on using TailwindCSS v4 with Phoenix, see the [Horizon project documentation](https://hex.pm/packages/horizon).

## Pre-built Binaries

Download or reference ready-to-use binaries:

- [tailwindcss-freebsd-x64 3.4.13](https://github.com/jfreeze/tailwind-freebsd-builder/releases/download/3.4.13/tailwindcss-freebsd-x64)
- [tailwindcss-freebsd-x64 3.4.17](https://github.com/jfreeze/tailwind-freebsd-builder/releases/download/3.4.17/tailwindcss-freebsd-x64)

Additional tailwind FreeBSD binaries are also available from [DCH's site](https://people.freebsd.org/~dch/pub/tailwind/).