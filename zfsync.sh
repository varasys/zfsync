#!/bin/sh
# ©, 2020, Casey Witt
# developed with zfs-0.8.3
# hosted at https://github.com/varasys/zfsync
# based on posix scripting tutorials at:
#   https://www.grymoire.com/Unix/Sh.html
#   https://steinbaugh.com/posts/posix.html
#   https://github.com/dylanaraps/pure-sh-bible

# note that ~/.ssh/authorized_keys file on the backup server must have an entry of the following form:
# command="zfsync.sh recv pool/path" <type> <key> [comment]
# synced datasets will be at pool/path

# TODO config zfsync user (as sender and receiver)
# TODO implement pruning
# TODO update sync logic to check for new latest snapshot after each send
# TODO implement creating dummy datasets on backup server for broken chains

set -eu # fast fail on errors and undefined variables

SNAPPREFIX="${SNAPPREFIX:-"zfsync_"}" # prefix for snapshot name
DATECMD="${DATECMD:-"date -u +%F_%H-%M-%S_UTC"}" # command to generate snapshot name timestamp

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

iterate() ( # call this to return ordered list of datasets to operate on
  # use this to return same list for both snap and sync
  ROOT="$1"
  SUFFIX="${2:-}"
  zfs list -r -Ho name,com.sun:auto-snapshot -s name "${ROOT}" \
    | awk -v suf="${SUFFIX}" '{ if ($2 != "false") print $1 suf }'
)

snap() (
  ROOT="${1:-"zpool"}"
  SNAPSHOT="${SNAPPREFIX}$(${DATECMD})"
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

connect() { # do not use subshell since RPC must be exported
  HOST="$1"
  SOCKET="${HOME}/.ssh/zfsync_${HOST}_$(date +%s%N)"
  log 'connecting to ssh host: %s ...' "${HOST}"
  ssh -fMN -S "${SOCKET}" "${HOST}"
  # shellcheck disable=2064 # expand HOST and SOCKET at definition time
  trap "disconnect '${HOST}' '${SOCKET}'" EXIT INT
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
    STATUS="$(zfs send -DLecwhp "${FIRST}" | mbuffer | $RPC recv "${SOURCE}")"
    printf '%s' "${STATUS}"
  fi
)

resume_remote() (
  SOURCE="$1"
  TOKEN="$2"
  log 'resuming send for %s' "${SOURCE}"
  STATUS="$(zfs send -e -t "${TOKEN}" | mbuffer | $RPC recv "${SOURCE}")"
  printf '%s' "${STATUS}"
)

update_remote() (
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
  STATUS="$(zfs send -DLecwhp -I "${STARTSNAP}" "${FINISHSNAP}" | mbuffer | $RPC recv "${SOURCE}")"
  printf '%s' "${STATUS}"
)

sync() ( # this is run on the machine to be backed up
  HOST="${1:-"localhost"}"
  ROOT="${2:-"zpool"}"
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

list() (
  HOST="$1"
  shift
  connect "$HOST" # this will define RPC variable
  $RPC list "$@"
)

send() (
  HOST="$1"
  shift
  connect "$HOST" # this will define RPC variable
  $RPC send "$@"
)

server() ( # run from authorized_keys file on the backup server (ie. command="zfsync.sh recv zpool/backups")
  TARGET="${1:-"zpool/backups"}" # the dataset path prefix including pool name (ie. zpool/backups)
  if ! zfs list "${TARGET}" >/dev/null 2>&1; then
    warn 'creating backup root dataset: %s' "${TARGET}"
    zfs create -o encryption=off -o canmount=noauto -o com.sun:auto-snapshot=false "$TARGET"
  fi
  # shellcheck disable=2086 # use word splitting below
  set -- $SSH_ORIGINAL_COMMAND
  SUBCMD="$1"
  shift
  case "${SUBCMD}" in
    'status')
      SOURCE="$1"
      if RESUME="$(zfs list -Ho receive_resume_token "${TARGET}/${SOURCE}" 2>/dev/null)" && [ "${RESUME}" != '-' ]; then
        printf 'receive_resume_token=%s' "${RESUME}"
      elif GUID="$(zfs list -t snapshot -Ho guid -S creation "${TARGET}/${SOURCE}" 2>/dev/null | head -n 1)" && [ -n "${GUID}" ]; then
        printf 'guid=%s' "${GUID}"
      fi
      ;;
    'recv')
      SOURCE="$1"
      mbuffer | zfs receive -s \
        -o canmount=noauto \
        -o com.sun:auto-snapshot=false \
        "${TARGET}/${SOURCE}" >&2
      SSH_ORIGINAL_COMMAND="status ${SOURCE}" recv "${TARGET}"
      ;;
    'send')
      ARGS="$*"
      OPTIONS="${ARGS% *}"
      DATASET="${ARGS##* }"
      [ "${OPTIONS}" != "${DATASET}" ] || OPTIONS=""
      # shellcheck disable=2086 # don't quote OPTIONS
      zfs send ${OPTIONS} "${TARGET}/${DATASET}"
      ;;
    'list')
      ARGS="$*"
      OPTIONS="${ARGS% *}"
      DATASET="${ARGS##* }"
      [ "${OPTIONS}" != "${DATASET}" ] || OPTIONS=""
      # shellcheck disable=2086 # don't quote OPTIONS
      zfs list ${OPTIONS} "${TARGET}/${DATASET}"
      ;;
    *)
      #shellcheck disable=2016 # don't expand %s below
      printf 'fatal error: unknown command `%s`\n' "$SSH_ORIGINAL_COMMAND"
      exit 1
      ;;
  esac
)

configuser() (
  USER="${1:-"zfsync"}"
  HOMEDIR="${2:-"${HOMEDIR:-"/etc/zfsync"}"}"
  if id "${USER}" >/dev/null 2>&1; then
    warn 'user %s already exists' "${USER}"
  else
    useradd --home-dir "${HOMEDIR}" --no-create-home \
      --shell "$(command -v bash || command -v sh)" --system "${USER}"
    log 'user %s created' "${USER}"
  fi
  if [ -d "${HOMEDIR}" ]; then
    warn 'home directory %s already exists' "${HOMEDIR}"
  else
    mkdir -p "${HOMEDIR}"
    chown "${USER}:${USER}" "${HOMEDIR}"
    log 'home directory %s created' "${HOMEDIR}"
  fi
  if [ -f "${HOMEDIR}/.ssh/id_ed25519" ]; then
    warn 'ssh key %s already exists' "${HOMEDIR}/.ssh/id_ed25519"
  else
    su -c "ssh-keygen -f '${HOMEDIR}/.ssh/id_ed25519' -t ed25519 -N ''" - "${USER}"
    ln -s .ssh "${HOMEDIR}/ssh"
    log 'ssh key %s created' "${HOMEDIR}/.ssh/id_ed25519"
  fi
)

restart_as_root() {
  if [ "$(id -u)" -ne 0 ]; then
    warn "restarting as root ..."
    exec sudo -E "$0" "$@"
  fi
}

allowsend() (
  DATASET="$1"
  USER="${2:-"zfsync"}"
  log "granting send permission to '%s' on dataset '%s'" "${USER}" "${DATASET}"
  zfs allow -dlg "${USER}" send "${DATASET}"
  zfs allow "${DATASET}"
)

allowreceive() (
  DATASET="$1"
  USER="${2:-"zfsync"}"
  log "granting receive,mount,create permission to '%s' on dataset '%s'" "${USER}" "${DATASET}"
  zfs allow -dlg "${2:-"zfsync"}" receive,mount,create "${DATASET}"
  zfs allow "${DATASET}"
)

showkey() (
  USER="${1:-"zfsync"}"
  if [ -z "${DATASET:-}" ]; then
    printf 'enter backup server dataset root (ie. zpool/backups): '
    read -r DATASET
    [ -n "${DATASET}" ] || DATASET="zpool/backups"
  fi
)

CMD="${1:-}"
[ $? -gt 0 ] && shift
case "${CMD}" in
  'snap')
    # help: \nsnap: recursively create new snapshots
    # help:   zfsync.sh snap <dataset>
    snap "$@";;
  'sync')
    # help: \nsync: recursively backup snapshots to remote server
    # help:   zfsync.sh sync <host> <dataset>
    sync "$@";;
  'server')
    # help: \nserver: run in server mode on the backup host (from .ssh/authorized_keys file)
    # help:   zfsync.sh server <dataset>
    server "$@";;
  'list')
    # help: \nlist: run `zfs list` remotely on backup server (ie. query the backup server from the client)
    # help:   zfsync.sh list <host> [options] <dataset>
    list "$@";; # host [options] dataset
  'send')
    # help: \nsend: run `zfs send` remotely on backup server (ie. to restore a snaphshot from the backup server)
    # help:   zfsync.sh send <host> [options] <dataset>
    send "$@";; # host [options] dataset
  'configuser')
    # help: \nconfiguser: create zfsync user, /etc/zfsync directory, and /etc/zfsync/.ssh/id_ed25519 ssh key
    # help:   zfsync configuser [username]
    restart_as_root configuser "$@"
    configuser "$@";;
  'allowsend')
    # help: \nallowsend: add zfs "send" permission for zfsync user to dataset (on client machine)
    # help:   zfsync allowsend <dataset> [username]
    restart_as_root allowsend "$@"
    allowsend "$@";;
  'allowreceive')
    # help: \nallowreceive: add zfs "receive,mount,create" permission for zfsync user to dataset (on backup server)
    # help:   zfsync allowreceive <dataset> [username]
    restart_as_root allowreceive "$@"
    allowreceive "$@";;
  'showkey')
    # help: \nshow line to add to backup server authorized_keys file (run on client)
    # help:   zfsync.sh showkey <dataset> [user]
    showkey "$@";;
  *)
    error "\nfatal error: unknown command%s" "${CMD:+": \`${CMD}\`"}"
    grep '# help: ' "$0" | grep -v 'grep' | sed 's/ *# help: //g' | sed 's/\\n/\n/g'
    ;;
esac
