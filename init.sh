#!/usr/bin/env sh

SOURCE="source"
TARGET="target"

[ -f "${SOURCE}.zfs" ] || truncate -s 512M "${SOURCE}.zfs"
# printf "%szfs\n%szfs\n" "${SOURCE}" "${SOURCE}" | zpool create -O compression=on -O encryption=on -O keyformat=passphrase "${SOURCE}" "${SOURCE}.zfs"

[ -f "${TARGET}.zfs" ] || truncate -s 512M "${TARGET}.zfs"
# printf "%szfs\n%szfs\n" "${TARGET}" "${TARGET}" | zpool create -O compression=on -O encryption=on -O keyformat=passphrase "${TARGET}" "${TARGET}.zfs"
