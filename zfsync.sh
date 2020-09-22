#!/usr/bin/env sh
# based on posix scripting tutorial at: https://www.grymoire.com/Unix/Sh.html
set -eu
# set -x

SOURCE="${SOURCE="source"}"
TARGET="${TARGET="target"}"

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
  for dataset in "nosync" "sync" "sync/first" "sync/second"; do
    create_dataset "${SOURCE}/${dataset}"
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

sync() {
  echo "not implemented yet"
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
