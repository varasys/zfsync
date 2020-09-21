#!/usr/bin/env sh
set -eEuo pipefail
set -x

WORKDIR="$(realpath "$(dirname "$0")")"
SOURCE="source"
TARGET="target"
SOURCEFILE="${WORKDIR}/${SOURCE}.zfs"
TARGETFILE="${WORKDIR}/${TARGET}.zfs"


[ -f "${SOURCEFILE}" ] || truncate -s 512M "${SOURCEFILE}"
zpool list "${SOURCE}" > /dev/null 2>&1 \
  || printf "%szfs\n%szfs\n" "${SOURCE}" "${SOURCE}" \
    | zpool create -O compression=on -O encryption=on -O keyformat=passphrase "${SOURCE}" "${SOURCEFILE}"

[ -f "${TARGETFILE}.zfs" ] || truncate -s 512M "${TARGETFILE}"
zpool list "${TARGET}" > /dev/null 2>&1 \
  || printf "%szfs\n%szfs\n" "${TARGET}" "${TARGET}" \
    | zpool create -O compression=on -O encryption=on -O keyformat=passphrase "${TARGET}" "${TARGETFILE}"
