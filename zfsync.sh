#!/bin/bash
# ©, 2020, Casey Witt
# developed for zfs-0.8.3
# hosted at https://github.com/varasys/zfsync
# based on posix scripting tutorials at:
#   https://www.grymoire.com/Unix/Sh.html
#   https://steinbaugh.com/posts/posix.html

# TODO accomidate adding new datesets to the source (currently need to manually sync first)
# TODO accomidate pruning old snapshots that don't have holds (currently does not do this at all)
# TODO handle failure and resume gracefully
# TODO add function to delete old snapshots
# TODO use -s flag with `zfs receive` to implement resuming failed receives

# note that ~/.ssh/authorized_keys file must have an entry of the following form:
# command="zfsync.sh recv pool/path" type key comment
# and ~/.ssh/config file should have an entry for the backup server including ControlMaster=auto
# and ControlPath=zfsync_%C

set -eu # fast fail on errors and undefined variables
# set -x

# prefix for snapshots
SNAPPREFIX="${SNAPPREFIX:-"zfsync_"}"

if [ "$(id -u)" -ne 0 ]; then
  printf "restarting as root ...\n"
  exec sudo -E "$0" "$@"
fi

log() {
  msg="\e[1m$1\e[0m"; shift
  # shellcheck disable=2059 # allow variable in printf format string
  printf "$msg\n" "$@" >&2
}

warn() {
  msg="\e[1m\e[35m$1\e[0m"; shift
  # shellcheck disable=2059 # allow variable in printf format string
  printf "$msg\n" "$@" >&2
}

error() {
  msg="\e[1m\e[31m$1\e[0m"; shift
  # shellcheck disable=2059 # allow variable in printf format string
  printf "$msg\n" "$@" >&2
}

iterate() {
  zfs list -r -Ho name,com.sun:auto-snapshot -s name "$1" \
    | awk '{ if ($2 != "false") print $1 }'
}

snap() {
  # shellcheck disable=2086 # no quotes needed around date args in the following line
  TIMESTAMP="$(date ${DATEARGS:--u +%F_%H-%M-%S_Z})"
  for dataset in $(iterate "$1"); do
    log "creating snapshot: %s" "${dataset}@${SNAPPREFIX}${TIMESTAMP}"
    zfs snap "${dataset}@${SNAPPREFIX}${TIMESTAMP}"
  done
}

sync() {
  HOST="$1"
  POOL="$2"
  # ssh -fN "$HOST"
  # shellcheck disable=2064 # expand HOST at trap definition
  # trap "$(command -v ssh) -O exit $HOST" EXIT INT TERM

  for FILESYSTEM in $(iterate "$POOL"); do
    log "syncing dataset: %s" "$FILESYSTEM"
    # remove the pool name prefix
    DATASET="${FILESYSTEM#*/}"
    # shellcheck disable=2029 # expand DATASET on client side
    LATEST="$(zfs list -t snap -Ho name "$FILESYSTEM" | ssh "$HOST" list "$DATASET")"
    if [ -n "$LATEST" ]; then
      RESUMETOKEN="${LATEST##*@}"
      SNAPSHOT="${LATEST%%@*}"
      printf "executing incremental from %s with resume token %s\n" "$SNAPSHOT" "$RESUMETOKEN"
      if [ "$RESUMETOKEN" != "-" ]; then
        # shellcheck disable=2029 # expand DATASET on client side
        zfs send -t "$RESUMETOKEN" | mbuffer | ssh "$HOST" 'recv' "$DATASET"
      fi
      # shellcheck disable=2029 # expand DATASET on client side
      zfs send -w -I "@$SNAPSHOT" "$FILESYSTEM@$(zfs list -t snap -o name "$DATASET" | tail -n 1)" \
        | mbuffer \
        | ssh "$HOST" 'recv' "$DATASET"
    else
      echo "executing initial transfer"
    fi
  done
}

recv() {
  TARGET="$1"
  log "client side working on: %s" "$TARGET"
  # shellcheck disable=2086 # use word splitting below
  set -- $SSH_ORIGINAL_COMMAND
  case "$1" in
    'list')
      POOL="$2"
      LATEST="$(cut -f 2 -d '@' \
        | comm -12 <(zfs list -t snap -Ho name "$TARGET/$POOL" 2>/dev/null | cut -f 2 -d '@') - \
        | tail -n 1)"
      if [ -n "$LATEST" ]; then
        printf "%s@%s" "$LATEST" "$(zfs list -Ho receive_resume_token "$TARGET/$POOL@$LATEST")"
      fi
      ;;
    'recv')
      echo "creating $TARGET"
      zfs create -p "$TARGET"
      mbuffer | zfs receive -s -d \
        -o com.sun:auto-snapshot=false \
        -o canmount=noauto \
        "$TARGET"
      ;;
    'connect')
      # do nothing
      ;;
    *)
      printf "fatal error: unknown command \`%s\`\n" "$SSH_ORIGINAL_COMMAND"
      exit 1
      ;;
  esac
}

case "${1-'sync'}" in
  'snap')
    shift
    snap "${1:-"zpool"}"
    ;;
  'sync')
    shift
    sync "${1:-"localhost"}" "${2:-"zpool"}"
    ;;
  'recv')
    # run this in ssh command options in authorized keys file with pool/root argument
    shift
    recv "${1:-"backup"}"
    ;;
  'holds') # from: https://serverfault.com/questions/456301/how-to-check-that-all-zfs-snapshots-within-a-pool-are-without-holds-before-destr#877160
    # this is for information only
    # shellcheck disable=2039 # ignore posix warning below and eventually work out a better way to do this
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
