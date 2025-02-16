Build CLI for TailwindCSS on FreeBSD.

## Usage

Note: you will need to check out a tagged version that corresponds to either a 3.x or a 4.x build.

```shell
git clone git@github.com:jfreeze/tailwind-freebsd-builder.git
cd tailwind-freebsd-builder
#git checkout 3.4.17
git checkout 4.0.6

cd src
./config.sh
./setup-tailwind-build.sh
./build-tailwindcss.sh -v -k -c
```

## Release

You can also download a binary release directly.

- [tailwindcss-freebsd-x64 3.4.17](https://github.com/jfreeze/tailwind-freebsd-builder/releases/download/3.4.17/tailwindcss-freebsd-x64)