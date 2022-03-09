#!/bin/sh
# ©, 2020, Casey Witt
# developed for zfs-0.8.4-1
# hosted at https://github.com/varasys/zfsync
# based on posix scripting tutorials at:
#   https://www.grymoire.com/Unix/Sh.html
#   https://steinbaugh.com/posts/posix.html

# create test bed environment for developing/debugging zfsync.sh


set -eu # fast fail on errors and undefined variables
# set -x

[ "$(id -u)" -ne 0 ] && {
  printf "restarting as root ...\n"
  exec sudo "$0" "$@"
}

# define these in the environment to change them
SOURCE="${SOURCE:-"source"}"
TARGET="${TARGET:-"target"}"
DATASET="${DATASET="sync"}"

WORKDIR="${WORKDIR:="$(realpath "$(pwd)")/workdir"}"
mkdir -p "${WORKDIR}"

# create backing files and zpool for testing
SOURCEFILE="${WORKDIR}/${SOURCE}.zfs"
TARGETFILE="${WORKDIR}/${TARGET}.zfs"
PASSWORDFILE="${WORKDIR}/password"

# delete old stuff if "clean" arg provided
if [ "${1-""}" = 'clean' ]; then
  printf "\nremoving existing zpools and backing files ...\n"

  delete_zpool() {
    if zpool list "$1" > /dev/null 2>&1; then
      printf "destroying zpool: '%s' ..." "$1"
      zpool destroy "$1" \
        || printf "zpool '%s' could not be destroyed (try manually with -f option)\n" "$1"
      printf " finished\n"
    fi
  }

  delete_backing_file() {
    if [ -f "$1" ]; then
      printf "removing backing file: '%s' ..." "$1"
      rm "$1"
      printf " finished\n"
    fi
  }

  delete_zpool "${SOURCE}"
  delete_zpool "${TARGET}"
  delete_backing_file "${SOURCEFILE}"
  delete_backing_file "${TARGETFILE}"
  printf "finished removing zpools and backing files\n"
fi

create_backing_file() {
  if [ -f "$1" ]; then
    printf "backing file: '%s' already exists\n" "$1"
  else
    printf "creating backing file: '%s' ..." "$1"
    truncate -s 512M "$1"
    printf " finished\n"
  fi
}

create_zpool() {
  if zpool list "$1" > /dev/null 2>&1; then
    printf "zpool: '%s' already exists\n" "$1"
  else
    if [ ! -f "${PASSWORDFILE}" ]; then
      printf 'enter new password: '
      read -r PASSWORD
      echo "${PASSWORD}" > "${PASSWORDFILE}"
    fi
    printf "creating zpool: '%s' ..." "$1"
    zpool create -O compression=on -O encryption=on -O keyformat=passphrase -O keylocation="file://${PASSWORDFILE}" "$1" "$2"
    printf " finished\n"
  fi
}

create_dataset() {
  if zfs list -t filesystem "$1" > /dev/null 2>&1; then
    printf "dataset: '%s' already exists\n" "$1"
  else
    printf "creating dataset: '%s' ..." "$1"
    zfs create "$1"
    printf " finished\n"
  fi
}

printf "\ncreating testing backing files and zpools ...\n"

create_backing_file "${SOURCEFILE}"
create_backing_file "${TARGETFILE}"
create_zpool "${SOURCE}" "${SOURCEFILE}"
create_zpool "${TARGET}" "${TARGETFILE}"
for filesystem in "no${DATASET}" "${DATASET}" "${DATASET}/first" "${DATASET}/second" "${DATASET}/second/deeper"; do
  echo "creating '${SOURCE}/${filesystem}"
  create_dataset "${SOURCE}/${filesystem}"
done
zfs set com.sun:auto-snapshot=false "${SOURCE}/no${DATASET}"
zfs set com.sun:auto-snapshot=false "${TARGET}"
printf "finished creating testing backing files and zpools\n"

printf "\ncurrent zpools:\n"
zpool list
printf "\nsource datasets:\n"
zfs list -r "${SOURCE}"
printf "\ntarget datasets:\n"
zfs list -r "${TARGET}"
printf "\n"
