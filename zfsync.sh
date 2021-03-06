#!/usr/bin/env sh
# ©, 2020, Casey Witt
# developed for zfs-0.8.4-1
# hosted at https://github.com/varasys/zfsync
# based on posix scripting tutorials at:
#   https://www.grymoire.com/Unix/Sh.html
#   https://steinbaugh.com/posts/posix.html


# TODO accomidate adding new datesets to the source (currently need to manually sync first)
# TODO accomidate pruning old snapshots that don't have holds (currently does not do this at all)
# TODO handle failure and resume gracefully
# TODO add function to delete old snapshots
# TODO use -s flag with `zfs receive` to implement resuming failed receives

set -eu # fast fail on errors and undefined variables
# set -x

# define these in the environment to change them
SOURCE="${SOURCE:-"source"}"
TARGET="${TARGET:-"target"}"
DATASET="${DATASET="/sync"}"

WORKDIR="${WORKDIR:="$(realpath "$(pwd)")"}"

sync() {
  TIMESTAMP="$(date -u +%F_%H-%M-%S_Z)"
  # use mbuffer to monitor throughput if available
  BUFFER="$(command -v mbuffer)"

  init() {
    printf "\ninitiating initial sync: %s ...\n" "${TIMESTAMP}"

    zfs send -LRw "${SOURCE}${DATASET}@${TIMESTAMP}" \
      | "${BUFFER}" -s 128k -m 500M \
      | zfs receive -o canmount=noauto -Fsv "${TARGET}/${SOURCE}"

    printf "\napplying holds ..."
    zfs hold -r "io.varasys.zfsync: ${TARGET}" "${SOURCE}${DATASET}@${TIMESTAMP}"
    zfs hold -r "io.varasys.zfsync: ${SOURCE}" "${TARGET}/${SOURCE}@${TIMESTAMP}"
    printf " finished\n"

    printf "\nfinished initial sync\n\n"
  }

  sync() {
    printf "\ninitiating sync: %s ...\n" "${TIMESTAMP}"
    LASTSNAP="$( \
      zfs list -o name -t snapshot "${TARGET}/${SOURCE}" \
      | sort -r \
      | head -n 1 \
    )"
    LAST="${LASTSNAP##*@}" # use replacement to get snapshot part only

    zfs send -LRw -I "@${LAST}" "${SOURCE}${DATASET}@${TIMESTAMP}" \
      | "${BUFFER}" -s 128k -m 500M \
      | zfs receive -Fsv "${TARGET}/${SOURCE}"

    printf "\napplying holds ..."
    zfs hold -r "io.varasys.zfsync: ${TARGET}" "${SOURCE}${DATASET}@${TIMESTAMP}"
    zfs hold -r "io.varasys.zfsync: ${SOURCE}" "${TARGET}/${SOURCE}@${TIMESTAMP}"
    printf " finished\n"

    printf "\nreleasing old holds ..."
    zfs release -r "io.varasys.zfsync: ${TARGET}" "${SOURCE}${DATASET}@${LAST}"
    zfs release -r "io.varasys.zfsync: ${SOURCE}" "${TARGET}/${SOURCE}@${LAST}"
    printf " finished\n"

    printf "\nfinished sync\n\n"
  }

  # take the snapshot early so if the script fails at least the snapshot will be taken
  zfs snapshot -r "${SOURCE}${DATASET}@${TIMESTAMP}"

  if ! zpool list "${TARGET}" > /dev/null 2>&1; then # import the zpool since it is not already
    printf "\nimporting zpool: %s\n" "${TARGET}"
    trap 'zpool export "${TARGET}" && printf "exporting zpool: %s\n\n" "${TARGET}"' 0 # then export it again when script exits
    if [ "${TARGET}" = 'target' ]; then
      # when  testing with the backing file the file location must be specified
      zpool import -d "${WORKDIR}/${TARGET}.zfs" "${TARGET}"
    else
      # when a device is used zpool will scan for the pool automatically
      zpool import "${TARGET}"
    fi
  fi

  if ! zfs list -t snapshot "${TARGET}/${SOURCE}" > /dev/null 2>&1; then
    init
  else
    sync
  fi
}

init_test() {
  # create backing files and zpool for testing
  SOURCEFILE="${WORKDIR}/${SOURCE}.zfs"
  TARGETFILE="${WORKDIR}/${TARGET}.zfs"

  # delete old stuff if "clean" arg provided
  if [ "${1-''}" = 'clean' ]; then
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
  'holds') # from: https://serverfault.com/questions/456301/how-to-check-that-all-zfs-snapshots-within-a-pool-are-without-holds-before-destr#877160
    # this is for information only
    zfs get -Ht snapshot userrefs \
      | grep -v $'\t'0 \
      | cut -d $'\t' -f 1 \
      | tr '\n' '\0' \
      | xargs -0 zfs holds
    ;;
  *)
    printf "\nusage: %s ( init_test [clean] | sync )\n\n" "$(basename "$0")"
    ;;
esac
