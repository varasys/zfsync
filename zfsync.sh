#!/bin/sh
# ©, 2020, Casey Witt
# developed for zfs-0.8.3
# hosted at https://github.com/varasys/zfsync
# based on posix scripting tutorials at:
#   https://www.grymoire.com/Unix/Sh.html
#   https://steinbaugh.com/posts/posix.html
#   https://github.com/dylanaraps/pure-sh-bible

# TODO accomidate adding new datesets to the source (currently need to manually sync first)
# TODO accomidate pruning old snapshots that don't have holds (currently does not do this at all)
# TODO handle failure and resume gracefully
# TODO add function to delete old snapshots

# note that ~/.ssh/authorized_keys file on the backup server must have an entry of the following form:
# command="zfsync.sh recv pool/path" <type> <key> [comment]
# synced datasets will be at pool/path

set -eu # fast fail on errors and undefined variables
# set -x

# prefix for snapshots
SNAPPREFIX="${SNAPPREFIX:-"zfsync_"}"

log() (
  MSG="$1"; shift
  # shellcheck disable=2059 # allow variable in printf format string
  printf "\e[1m$MSG\e[0m\n" "$@" >&2
)

debug() (
  MSG="$1"; shift
  # shellcheck disable=2059 # allow variable in printf format string
  printf "\e[1m\e[96m$MSG\e[0m\n" "$@" >&2
)

warn() (
  MSG="$1"; shift
  # shellcheck disable=2059 # allow variable in printf format string
  printf "\e[1m\e[35m$MSG\e[0m\n" "$@" >&2
)

error() (
  MSG="$1"; shift
  # shellcheck disable=2059 # allow variable in printf format string
  printf "\e[1m\e[31m$MSG\e[0m\n" "$@" >&2
)

if [ "$(id -u)" -ne 0 ]; then
  warn "restarting as root ..."
  exec sudo -E "$0" "$@"
fi

iterate() ( # call this to return ordered list of datasets to operate on
  # use this to return same list for both snap and sync
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
    log 'creating snapshots:' >&2
    #shellcheck disable=2086 # do not quote $SNAPSHOTS
    zfs snap ${SNAPSHOTS}
    for SNAP in ${SNAPSHOTS}; do # create bookmark of each snapshot
      printf '%s\n' "${SNAP}"
      zfs bookmark "${SNAP}" "${SNAP%@*}#${SNAPSHOT}"
    done
  fi
)

connect() {
  HOST="$1"
  SOCKET="${HOME}/.ssh/zfsync_${HOST}_$(date +%s%N)"
  log 'connecting to ssh host: %s ...' "${HOST}"
  ssh -fMN -S "${SOCKET}" "${HOST}"
  # shellcheck disable=2064 # expand HOST and SOCKET at definition time
  trap "disconnect '${HOST}' '${SOCKET}'" EXIT
  RPC=$(printf '%s -o ControlMaster=no -S %s %s' "$(command -v ssh)" "${SOCKET}" "${HOST}")
  export RPC # need to export so function subshells have access
}

disconnect() (
  HOST="$1"
  SOCKET="$2"
  log 'disconnecting from ssh host: %s ...' "${HOST}"
  ssh -S "${SOCKET}" -O exit "${HOST}"
)

create_remote() (
  SOURCE="$1"
  FIRST=$(zfs list -t snap -Ho name -s creation "${SOURCE}" | head -n 1)
  if [ -z "$FIRST" ]; then
    error 'no snapshots available to sync dataset: %s' "$SOURCE"
  else
    log 'sending %s' "${SOURCE}"
    STATUS="$(zfs send -DLecwhp "${FIRST}" | mbuffer | $RPC sync "${SOURCE}")"
    printf '%s' "${STATUS}"
  fi
)

resume_remote() (
  SOURCE="$1"
  TOKEN="$2"
  log 'resuming send for %s' "${SOURCE}"
  STATUS="$(zfs send -e -t "${TOKEN}" | mbuffer | $RPC sync "${SOURCE}")"
  printf '%s' "${STATUS}"
)

update_remote() {
  SOURCE="$1"
  REMOTEGUID="$2"
  debug 'remote guid: %s for %s' "$REMOTEGUID" "$SOURCE"
  STARTSNAP="$(zfs list -Ho name,guid -t snapshot -s creation "${SOURCE}" \
    | awk "\$2 == ${REMOTEGUID} { print \$1 }")"
  debug 'first STARTSNAP: %s' "$STARTSNAP"
  [ -z "${STARTSNAP}" ] && STARTSNAP="$(zfs list -Ho name,guid -t bookmark -s creation "${SOURCE}" \
    | awk "\$2 == ${REMOTEGUID} { print \$1 }")"
  FINISHSNAP="$(zfs list -t snap -Ho name -S creation "${SOURCE}" | head -n 1)"
  debug 'second FINISHSNAP: %s' "$FINISHSNAP"

  log 'sending incremental %s' "${FINISHSNAP}"
  STATUS="$(zfs send -DLecwhp -I "${STARTSNAP}" "${FINISHSNAP}" | mbuffer | $RPC sync "${SOURCE}")"
  printf '%s' "${STATUS}"
}

sync() ( # this is run on the machine to be backed up
  HOST="$1"
  ROOT="$2"
  connect "$HOST" # this will define RPC variable
  log 'syncing to host: %s' "${HOST}"

  for SOURCE in $(iterate "${ROOT}"); do
    (
      debug 'syncing: %s' "$SOURCE"
      GUID="$(zfs list -t snap -Ho guid -S creation "${SOURCE}" | head -n 1)"
      debug 'current guid: %s' "$GUID"
      STATUS=$($RPC status "$SOURCE")
      error 'status: %s' "${STATUS}"
      until [ "${GUID}" = "${STATUS#guid=}" ]; do
        case "${STATUS}" in
          receive_resume_token=*)
            debug 'resuming: %s' "$STATUS"
            STATUS="$(resume_remote "${SOURCE}" "${STATUS#receive_resume_token=}")"
            ;;
          guid=*)
            debug 'updating: %s for %s' "$STATUS" "$SOURCE"
            STATUS="$(update_remote "${SOURCE}" "${STATUS#guid=}")"
            ;;
          *)
            debug 'creating: %s' "$STATUS"
            STATUS="$(create_remote "${SOURCE}")"
            ;;
        esac
      done
    ) || error 'error syncing %s' "${SOURCE}"
  done
)

recv() ( # run from authorized_keys file on the backup server (ie. command="zfsync.sh recv zpool/backups")
  TARGET="$1" # the dataset path prefix including pool name (ie. zpool/backups)
  if ! zfs list "${TARGET}" >/dev/null 2>&1; then
    warn 'creating backup root dataset: %s' "${TARGET}"
    zfs create -o encryption=off -o canmount=noauto -o com.sun:auto-snapshot=false "$TARGET"
  fi
  # shellcheck disable=2086 # use word splitting below
  set -- $SSH_ORIGINAL_COMMAND
  CMD="$1"
  SOURCE="$2"
  case "${CMD}" in
    'status')
      if RESUME="$(zfs list -Ho receive_resume_token "${TARGET}/${SOURCE}" 2>/dev/null)" && [ "${RESUME}" != '-' ]; then
        printf 'receive_resume_token=%s' "${RESUME}"
      elif GUID="$(zfs list -t snapshot -Ho guid -S creation "${TARGET}/${SOURCE}" 2>/dev/null | head -n 1)" && [ -n "${GUID}" ]; then
        printf 'guid=%s' "${GUID}"
      fi
      ;;
    'sync')
      #mbuffer | zfs receive -sv \
      mbuffer | zfs receive -s \
        -o canmount=noauto \
        -o com.sun:auto-snapshot=false \
        "${TARGET}/${SOURCE}" >&2
      SSH_ORIGINAL_COMMAND="status ${SOURCE}" recv "${TARGET}"
      ;;
    *)
      #shellcheck disable=2016 # don't expand %s below
      printf 'fatal error: unknown command `%s`\n' "$SSH_ORIGINAL_COMMAND"
      exit 1
      ;;
  esac
)

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
