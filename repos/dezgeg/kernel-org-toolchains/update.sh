#!/usr/bin/env bash

URL_BASE='https://mirrors.edge.kernel.org/pub/tools/crosstool/files/bin/x86_64/8.1.0/'
# The tarballs are named like this:
#   x86_64-gcc-8.1.0-nolibc-aarch64-linux.tar.xz
# so splitting on '-' gives you { [1] = native-arch, [2] = compiler, [3] = version, [4] = libc, [5] = target-arch, [6] = target-os + '.tar.xz' }

mkdir -p tarballs

(
    echo "# NOTE: This file is autogenerated by update.sh, do not edit manually!"
    cat default.nix.in
    echo "in {"
    curl "$URL_BASE" \
        | egrep -o 'href="[^"]*\.tar\.xz"' | tr '"' ' ' | awk '{ split($2, parts, "-"); printf("%s %s-%s %s\n", parts[5], parts[2], parts[3], $2); }' \
        | while read arch toolchain tarball rest; do
            wget -P tarballs -N "$URL_BASE/$tarball"
            sha256=$(sha256sum "tarballs/$tarball" | awk '{print $1}')
            echo "    $arch = fetchKernelOrgToolchain \"$toolchain\" \"$arch\" \"$tarball\" \"$sha256\";"
        done
    echo "}"
) > default.nix