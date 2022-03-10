#!/bin/sh
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

log() (
  MSG="\e[1m$1\e[0m"; shift
  # shellcheck disable=2059 # allow variable in printf format string
  printf "$MSG\n" "$@" >&2
)

warn() (
  MSG="\e[1m\e[35m$1\e[0m"; shift
  # shellcheck disable=2059 # allow variable in printf format string
  printf "$MSG\n" "$@" >&2
)

error() (
  MSG="\e[1m\e[31m$1\e[0m"; shift
  # shellcheck disable=2059 # allow variable in printf format string
  printf "$MSG\n" "$@" >&2
)

if [ "$(id -u)" -ne 0 ]; then
  warn "restarting as root ..."
  exec sudo -E "$0" "$@"
fi

iterate() ( # call this to return ordered list of datasets to operate on
  ROOT="$1"
  SUFFIX="${2:-}"
  zfs list -r -Ho name,com.sun:auto-snapshot -s name "${ROOT}" \
    | awk -v suf="${SUFFIX}" '{ if ($2 != "false") print $1 suf }'
)

snap() (
  ROOT="$1"
  # shellcheck disable=2086 # no quotes needed around date args in the following line
  TIMESTAMP="$(date ${DATEARGS:--u +%F_%H-%M-%S_Z})"
  SNAPSHOT="${SNAPPREFIX}${TIMESTAMP}"
  SNAPSHOTS=$(iterate "${ROOT}" "@${SNAPSHOT}")
  if [ -n "${SNAPSHOTS}" ]; then
    #shellcheck disable=2086 # do not quote $SNAPSHOTS
    zfs snap ${SNAPSHOTS}
    for SNAP in ${SNAPSHOTS}; do # create bookmark of each snapshot
      zfs bookmark "${SNAP}" "${SNAP%@*}#${SNAPSHOT}"
    done
  fi
)

connect() {
  RPC=$(
    HOST="$1"
    SOCKET="${HOME}/.ssh/zfsync_${HOST}_$(date +%s%N)"
    log 'connecting to ssh host: %s ...' "${HOST}"
    ssh -fMN -S "${SOCKET}" "${HOST}"
    # shellcheck disable=2064 # expand HOST and SOCKET at definition time
    trap "disconnect '${HOST}' '${SOCKET}'" EXIT
    printf '%s -o ControlMaster=no -S %s %s' "$(command -v ssh)" "${SOCKET}" "${HOST}"
  )
  export RPC # need to export so subshells have access
}

disconnect() (
  HOST="$1"
  SOCKET="$2"
  log 'disconnecting from ssh host: %s ...' "${HOST}"
  ssh -S "${SOCKET}" -O exit "${HOST}"
)

create_remote() (
  SOURCE=$1
  warn 'creating remote dataset: %s' "$SOURCE"
  LATEST=$(zfs list -t snap -Ho name -s creation "${SOURCE}" | head -n 1)
  if [ -z "$LATEST" ]; then
    warn 'skipping dataset sync since it has no snapshots: %s' "$SOURCE"
  else
    error 'syncing %s' "${LATEST}"
    zfs send -DLecwhpP "${LATEST}" | mbuffer | $RPC sync "${SOURCE}"
    printf '%s' "${LATEST}" # return for use in subsequent sync statement
  fi
)

sync_remote() (
  SOURCE=$1
  warn 'syncing remote dataset: %s' "$SOURCE"
)

sync() ( # this is run on the machine to be backed up
  HOST="$1"
  ROOT="$2"
  connect "$HOST" # this will define RPC variable
  log 'syncing to host: %s' "${HOST}"

  for SOURCE in $(iterate "${ROOT}"); do
    (
      log 'syncing dataset: %s' "${SOURCE}"
      LATEST=$($RPC latest "$SOURCE")
      if [ -z "$LATEST" ]; then
        create_remote "$SOURCE"
      fi
      sync_remote "$SOURCE"
    )
  done
)

recv() ( # run from authorized_keys file on the backup server (ie. command="zfsync.sh recv zpool/backups")
  TARGET="$1" # the dataset path prefix including pool name (ie. zpool/backups)
  if ! zfs list "${TARGET}" >/dev/null 2>&1; then
    warn 'creating backup root dataset: %s' "${TARGET}"
    zfs create -o canmount=noauto -o com.sun:auto-snapshot=false "$TARGET"
  fi
  # shellcheck disable=2086 # use word splitting below
  set -- $SSH_ORIGINAL_COMMAND
  CMD="$1"
  SOURCE="$2"
  case "${CMD}" in
    'latest')
      # return the name, and receive_resume_token of the latest snapshot
      zfs list -t snapshot -Ho name,receive_resume_token -S creation "${TARGET}/${SOURCE}" | head -n 1
      ;;
    'sync')
      mbuffer | zfs receive -sv \
        -o canmount=noauto \
        -o com.sun:auto-snapshot=false \
        "${TARGET}/${SOURCE}"
      ;;
    *)
      #shellcheck disable=2016 # don't expand %s below
      printf 'fatal error: unknown command `%s`\n' "$SSH_ORIGINAL_COMMAND"
      exit 1
      ;;
  esac
)

syncOLD() {
  HOST="$1"
  ROOT="$2"
  connect "$HOST"

  for SOURCE in $(iterate "$ROOT"); do
    log "syncing dataset: %s" "$SOURCE"
    TARGET="${SOURCE#*/}" # remove the pool name prefix
    # shellcheck disable=2029 # expand TARGET on client side
    LATEST="$(zfs list -t snap -Ho name "$SOURCE" | cut -f 2 -d '@' | ssh "$HOST" list "$TARGET")"
    if [ -n "$LATEST" ]; then
      RESUMETOKEN="${LATEST##*@}"
      SNAPSHOT="${LATEST%%@*}"
      log "executing incremental from %s with resume token %s" "$SNAPSHOT" "$RESUMETOKEN"
      if [ "$RESUMETOKEN" != "-" ]; then
        # shellcheck disable=2029 # expand TARGET on client side
        zfs send -t "$RESUMETOKEN" | mbuffer | ssh "$HOST" 'recv' "$TARGET"
      fi
      # shellcheck disable=2029 # expand TARGET on client side
      zfs send -w -I "@$SNAPSHOT" "$SOURCE@$(zfs list -t snap -o name "$TARGET" | tail -n 1)" \
        | mbuffer \
        | ssh "$HOST" 'recv' "$TARGET"
    else
      echo "executing initial transfer"
    fi
  done
}

case "${1:-""}" in
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
    error "\nfatal error: unknown command%s" "${1:+": \`$1\`"}"
    error "usage: %s snap | sync | recv | holds" "$(basename "$0")"
    ;;
esac
