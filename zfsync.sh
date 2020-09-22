#!/usr/bin/env sh
# based on posix scripting tutorial at: https://www.grymoire.com/Unix/Sh.html
set -eu # fast fail on errors and undefined variables
# set -x

# define these in the environment to change them
SOURCE="${SOURCE="source"}"
TARGET="${TARGET="target"}"
DATASET="${DATASET="sync"}"

sync() {
  TIMESTAMP="$(date -u +%F_%H-%M-%S_Z)"
  # use pv to monitor throughput if available
  PV="$(command -v pv || command -v cat)"

  init() {
    printf "\ninitiating initial sync: %s ...\n" "${TIMESTAMP}"
    zfs snapshot -r "${SOURCE}/${DATASET}@${TIMESTAMP}"
    zfs send -LRw "${SOURCE}/${DATASET}@${TIMESTAMP}" \
      | "${PV}" \
      | zfs receive -Fv "${TARGET}/${SOURCE}"
    printf "\nfinished initial sync\n\n"
  }

  sync() {
    printf "sync not implemented yet\n"
  }

  if ! zfs list "${TARGET}/${SOURCE}" > /dev/null 2>&1; then
    init
  else
    sync
  fi
}

init_test() {
  # create backing files and zpool for testing
  WORKDIR="${WORKDIR="$(realpath "$(pwd)")"}"
  SOURCEFILE="${WORKDIR}/${SOURCE}.zfs"
  TARGETFILE="${WORKDIR}/${TARGET}.zfs"

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
      printf "creating zpool: '%s' ..." "$1"
      printf "%szfs\n%szfs\n" "$1" "$1" \
        | zpool create -O compression=on -O encryption=on -O keyformat=passphrase "$1" "$2"
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
    create_dataset "${SOURCE}/${filesystem}"
  done
  printf "finished creating testing backing files and zpools\n"

  printf "\ncurrent zpools:\n"
  zpool list
  printf "\nsource datasets:\n"
  zfs list -r "${SOURCE}"
  printf "\ntarget datasets:\n"
  zfs list -r "${TARGET}"
  printf "\n"
}

case "${1-'sync'}" in
  'init_test')
    shift
    init_test "$@"
    ;;
  'sync')
    shift
    sync "$@"
    ;;
  *)
    printf "\nusage: %s ( init_test [clean] | sync )\n\n" "$(basename "$0")"
    ;;
esac
