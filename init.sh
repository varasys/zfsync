#!/usr/bin/env sh
set -euo

WORKDIR="$(realpath "$(pwd)")"
SOURCE="source"
TARGET="target"
SOURCEFILE="${WORKDIR}/${SOURCE}.zfs"
TARGETFILE="${WORKDIR}/${TARGET}.zfs"


# create source
[ -f "${SOURCEFILE}" ] || {
  printf "creating source file: %s\n" "${SOURCEFILE}"
  truncate -s 512M "${SOURCEFILE}"
}
zpool list "${SOURCE}" > /dev/null 2>&1 || {
  printf "creating source zpool: %s\n" "${SOURCE}"
  printf "%szfs\n%szfs\n" "${SOURCE}" "${SOURCE}" \
    | zpool create -O compression=on -O encryption=on -O keyformat=passphrase "${SOURCE}" "${SOURCEFILE}"
}

# create target
[ -f "${TARGETFILE}" ] || {
  printf "creating target file: %s\n" "${TARGETFILE}"
  truncate -s 512M "${TARGETFILE}"
}
zpool list "${TARGET}" > /dev/null 2>&1 || {
  printf "creating target zpool: %s\n" "${TARGET}"
  printf "%szfs\n%szfs\n" "${TARGET}" "${TARGET}" \
    | zpool create -O compression=on -O encryption=on -O keyformat=passphrase "${TARGET}" "${TARGETFILE}"
}

# yeah - finished
printf "\nfinished\n\n"
