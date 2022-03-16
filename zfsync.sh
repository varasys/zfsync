#!/usr/bin/env bash
# ©, 2022, Casey Witt
# developed with zfs-0.8.3
# hosted at https://github.com/varasys/zfsync
# script linted with shellcheck (https://www.shellcheck.net/)
# initially meant to be posix sh compatable, but could not work out reliable enough error handling with posix sh

# note that ~/.ssh/authorized_keys file on the backup server must have an entry of the following form:
# command="zfsync.sh server pool/path" ssh-ed25519 <key> [comment]

# [ ] TODO implement pre/post send/receive hooks (for cascade backups)
# [ ] TODO implement localhost mirroring (without ssh)
# [ ] TODO update sync logic to check for new latest snapshot after each send
# [ ] TODO implement pruning (maybe; consider this may be best for seperate script; or may be best for this script to prune on remote also)
# [ ] TODO implement creating dummy datasets on backup server for broken chains (probably not; let the user do this manually??)
# [*] TODO config zfsync user (as sender and receiver)

set -euo pipefail # fast fail on errors, undefined variables, and pipeline errors

AUTOSNAPPROP="${AUTOSNAPPROP:-"com.sun:auto-snapshot"}" # dataset user property (set false to exclude dataset from snapshoting and backups)
SNAPPREFIX="${SNAPPREFIX:-"zfsync_"}" # prefix for snapshot name
DATECMD="${DATECMD:-"date -u +%F_%H-%M-%S_UTC"}" # command to generate snapshot name timestamp

ERR=0 # error counter (incremented when error function is called)
trap 'exit $ERR' EXIT # note that the connect function redefines this if it is called

log() {
  MSG="$1"; shift
  # shellcheck disable=2059 # allow variable in printf format string
  printf "\e[1m${MSG}\e[0m\n" "$@" >&2
}

debug() {
  MSG="$1"; shift
  # shellcheck disable=2059 # allow variable in printf format string
  printf "\e[1m\e[4;36m${MSG}\e[0m\n" "$@" >&2
}

warn() {
  MSG="$1"; shift
  # shellcheck disable=2059 # allow variable in printf format string
  printf "\e[1m\e[35m${MSG}\e[0m\n" "$@" >&2
}

error() {
  MSG="$1"; shift
  # shellcheck disable=2059 # allow variable in printf format string
  printf "\e[1m\e[31m${MSG}\e[0m\n" "$@" >&2
  ERR=$((ERR+1))
}

fatal() {
  MSG="$1"; shift
  # shellcheck disable=2059 # allow variable in printf format string
  printf "\e[1m\e[31m${MSG}\e[0m\n" "$@" >&2
  exit 1
}

iterate() { # call this to return ordered list of datasets to operate on for snap and mirror
  ROOT="$1"
  SUFFIX="${2:-}"
  zfs list -r -Ho "name,${AUTOSNAPPROP}" -s name "${ROOT}" \
    | awk -v suf="${SUFFIX}" '{ if ($2 != "false") print $1 suf }'
}

snap() {
  SNAPSHOT="${SNAPPREFIX}$(${DATECMD})"
  # shellcheck disable=2015,2091 # accept logic and execute subcommand
  for ROOT in $([ $# -gt 0 ] && echo "$@" || zpool list -Ho name); do
    (
      # shellcheck disable=2030 # ERR is local to subshell
      ERR=0
      log 'creating snapshots for %s:' "${ROOT}"
      SNAPSHOTS="$(iterate "${ROOT}" "@${SNAPSHOT}")" || fatal 'error iterating %s' "${ROOT}"
      if [ -n "${SNAPSHOTS}" ]; then
        printf '%s\n' "${SNAPSHOTS}"
        #shellcheck disable=2086 # do not quote variables
        if [ -n "${PRESNAPHOOK:-}" ]; then # run pre-snapshot hook if it is defined
          ${PRESNAPHOOK} ${SNAPSHOTS} \
            || error 'error running PRESNAPHOOK: %s' "${PRESNAPHOOK}"
        fi
        #shellcheck disable=2086 # do not quote $SNAPSHOTS
        zfs snap ${SNAPSHOTS} || fatal 'error creating snaphots for %s' "${ROOT}"
        for SNAP in ${SNAPSHOTS}; do # create bookmark of each snapshot
          zfs bookmark "${SNAP}" "${SNAP%@*}#${SNAPSHOT}" \
            || error 'error creating bookmark %s' "${SNAP%@*}#${SNAPSHOT}"
        done
        #shellcheck disable=2086 # do not quote variables
        if [ -n "${POSTSNAPHOOK:-}" ]; then # run post-snapshot hook if it is defined
          ${POSTSNAPHOOK} ${SNAPSHOTS} \
            || error 'error running POSTSNAPHOOK: %s' "${POSTSNAPHOOK}"
        fi
      fi
      exit $ERR
    ) || {
      # shellcheck disable=2031 # ERR from subshell is $? in the following line
      ERR=$((ERR+$?))
    }
  done
}

connect() {
  if [ -z "${RPC:-}" ]; then # don't reconnect if $RPC is already defined
    HOST="$1"
    SOCKET="${HOME}/.ssh/zfsync_${HOST}_$(date +%s%N)"
    log 'connecting to ssh host: %s ...' "${HOST}"
    ssh -fMN -S "${SOCKET}" "${HOST}"
    # shellcheck disable=2064 # expand HOST and SOCKET at definition time
    trap "
      log 'disconnecting from ssh host: %s ...' '${HOST}'
      ssh -S '${SOCKET}' -O exit '${HOST}'
      exit \$ERR
    " EXIT
    RPC=$(printf '%s -o ControlMaster=no -S %s %s' "$(command -v ssh)" "${SOCKET}" "${HOST}")
    export RPC # need to export so function subshells have access
  fi
}

create_remote() {
  SOURCE="$1"
  FIRST=$(zfs list -t snap -Ho name -s creation "${SOURCE}" | head -n 1)
  zfs send -DLecwh "${FIRST}" | mbuffer | $RPC receive -s "${SOURCE}"
}

resume_remote() {
  SOURCE="$1"
  TOKEN="$2"
  zfs send -e -t "${TOKEN}" | mbuffer | $RPC receive -s "${SOURCE}"
}

update_remote() {
  SOURCE="$1"
  REMOTEGUID="$2"
  STARTSNAP="$(zfs list -Ho name,guid -t snapshot -s creation "${SOURCE}" \
    | awk "\$2 == ${REMOTEGUID} { print \$1 }")"
  # if STARTSNAP is not found then search bookmarks
  [ -n "${STARTSNAP}" ] || STARTSNAP="$(zfs list -Ho name,guid -t bookmark -s creation "${SOURCE}" \
    | awk "\$2 == ${REMOTEGUID} { print \$1 }")"
  [ -n "${STARTSNAP}" ] || { error "can't find snapshot/bookmark for guid=%s" "${REMOTEGUID}"; exit 1; }
  FINISHSNAP="$(zfs list -t snap -Ho name -S creation "${SOURCE}" | head -n 1)"
  zfs send -DLecwh -I "${STARTSNAP}" "${FINISHSNAP}" | mbuffer | $RPC receive -s "${SOURCE}"
}

mirror() { # this is run on the machine to be backed up
  # shellcheck disable=2015,2091 # accept logic and execute subcommand
  for ROOT in $([ $# -gt 0 ] && echo "$@" || zpool list -Ho name); do
    (
      for SOURCE in $(iterate "${ROOT}" || fatal 'failed to iterate %s' "${ROOT}"); do
        (
          log 'mirroring %s ...' "${SOURCE}"
          STATUS="$($RPC status "${SOURCE}")" || fatal 'error querying %s' "${SOURCE}"
          until
            debug "STATUS=%s" "$STATUS"
            GUID="$(zfs list -t snap -Ho guid -S creation "${SOURCE}" | head -n 1)" || fatal 'error querying guid for %s' "${SOURCE}"
            [ -z "${GUID}" ] && fatal "error mirroring %s - no existing snapshots" "${SOURCE}"
            [ "${GUID}" = "${STATUS#guid=}" ] && debug 'complete: %s synced to GUID=%s' "${SOURCE}" "${GUID}"
          do
            case "${STATUS}" in
              receive_resume_token=*)
                log '\nresuming: %s' "${SOURCE}"
                STATUS="$(resume_remote "${SOURCE}" "${STATUS#receive_resume_token=}")" || fatal 'error resuming %s' "${SOURCE}"
                ;;
              guid=*)
                log '\nupdating %s (%s => %s)' "${SOURCE}" "${STATUS}" "${GUID}"
                STATUS="$(update_remote "${SOURCE}" "${STATUS#guid=}")" || fatal 'error updating %s' "${SOURCE}"
                ;;
              *)
                log '\ncreating: %s' "${SOURCE}"
                STATUS="$(create_remote "${SOURCE}")" || fatal 'error creating remote %s' "${SOURCE}"
                ;;
            esac
          done
          exit $ERR
        ) || {
          # shellcheck disable=2030 # ERR from the subshell is $? below
          ERR=$((ERR+$?))
        }
      done
      exit $ERR
    ) || {
      # shellcheck disable=2031 # ERR from the subshell is $? below
      ERR=$((ERR+$?))
    }
  done
}

server() { # run from authorized_keys file on the backup server (ie. command="zfsync.sh receive zpool/backups")
  TARGET="$1" # the dataset path prefix including pool name (ie. zpool/backups)
  # shellcheck disable=2086 # use word splitting below
  set -- $SSH_ORIGINAL_COMMAND
  SUBCMD="$1"; shift
  case "${SUBCMD}" in
    status)
      SOURCE="$1"
      debug 'querying remote status for %s' "${SOURCE}"
      TOKEN="$(zfs list -Ho receive_resume_token "${TARGET}/${SOURCE}" 2>/dev/null)"
      if [ "${TOKEN}" = "-" ]; then # dataset exists so check for guid
        GUID="$(zfs list -t snapshot -Ho guid -S creation "${TARGET}/${SOURCE}" | head -n 1)"
        if [ -n "${GUID}" ]; then
          TOKEN="guid=${GUID}" # respond with the guid
        else
          TOKEN="detached" # the dataset exists, but has no snapshots
        fi
      elif [ -n "${TOKEN}" ]; then # there is a resume token (which is not '-') so use it
        TOKEN="receive_resume_token=${TOKEN}"
      else
        TOKEN='missing'
      fi
      debug '%s\n' "${TOKEN:-"something is wrong"}"
      printf '%s' "${TOKEN}"
      ;;
    recv|receive)
      ARGS="$*"
      OPTIONS="${ARGS% *}"
      DATASET="${ARGS##* }"
      [ "${OPTIONS}" != "${DATASET}" ] || OPTIONS=""
      # [ -n "${PRERECEIVEHOOK}" ] && { ${PRERECEIVEHOOK} "${TARGET}" || true; } # run pre-receive hook if defined
      # shellcheck disable=2086 # don't quote OPTIONS
      mbuffer | zfs receive ${OPTIONS} "${TARGET}/${DATASET}"
      # [ -n "${POSTRECEIVEHOOK}" ] && { ${POSTRECEIVEHOOK} "${TARGET}" || true; } # run post-receive hook if defined
      TOKEN="$(SSH_ORIGINAL_COMMAND="status ${DATASET}" server "${TARGET}")"
      debug 'post receive token: %s' "${TOKEN}"
      printf '%s' "${TOKEN}"
      ;;
    send|list|destroy)
      ARGS="$*"
      OPTIONS="${ARGS% *}"
      DATASET="${ARGS##* }"
      [ "${OPTIONS}" != "${DATASET}" ] || OPTIONS=""
      # shellcheck disable=2086 # don't quote OPTIONS
      zfs "${SUBCMD}" ${OPTIONS} "${TARGET}/${DATASET}"
      ;;
    *)
      #shellcheck disable=2016 # don't expand %s below
      error 'fatal error: unknown command `%s`\n' "$SSH_ORIGINAL_COMMAND"
      exit 1
      ;;
  esac
}

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
  PERMS="send,snapshot,bookmark,hold"
  log "granting '%s' permissions to '%s' on dataset '%s'" "${PERMS}" "${USER}" "${DATASET}"
  zfs allow -dlg "${USER}" "${PERMS}" "${DATASET}"
  zfs allow "${DATASET}"
)

allowreceive() (
  DATASET="$1"
  USER="${2:-"zfsync"}"
  PERMS='receive,mount,create,userprop,encryption,canmount,mountpoint,compression,destroy,send,bookmark,keylocation'
  if ! zfs list "${DATASET}" >/dev/null 2>&1; then
    warn 'creating dataset %s' "${DATASET}"
    zfs create -p "${DATASET}"
  fi
  log "granting '%s' permission to '%s' on dataset '%s'" "${PERMS}" "${USER}" "${DATASET}"
  zfs allow -dlg "${2:-"zfsync"}" "${PERMS}" "${DATASET}"
  zfs allow "${DATASET}"
)

showkey() (
  DATASET="${1:-"<dataset>"}"
  USER="${2:-"zfsync"}"
  if [ "$(id -un)" = "${USER}" ]; then
    KEY="$(cat "${HOME}/.ssh/id_ed25519.pub")"
  else
    KEY="$(sudo su -l -c "eval cat '\${HOME}/.ssh/id_ed25519.pub'" "${USER}")"
  fi
  log 'showing key for user: %s' "${USER}"
  # shellcheck disable=2016 # do not expand $HOME in the following line
  log 'copy the following line into the "$HOME/.ssh/authorized_keys" file on the backup server'
  [ "${DATASET}" = "<dataset>" ] && log 'change <dataset> to the root dataset for the backups on the backup server'
  printf '\ncommand="%s server %s" %s\n\n' "$(basename "$0")" "${DATASET}" "${KEY}"
)

CMD="${1:-}"
[ $# -gt 0 ] && shift
case "${CMD}" in
  snap)
    # help: \nsnap: recursively create new snapshots
    # help:   zfsync.sh snap [pool|dataset]
    snap "$@";;
  mirror)
    # help: \nsync: recursively mirror snapshots to remote server
    # help:   zfsync.sh mirror <host> [pool|dataset]
    HOST="$1"; shift
    connect "${HOST}"
    mirror "$@";;
  server)
    # help: \nserver: run in server mode on the backup host (from .ssh/authorized_keys file)
    # help:   zfsync.sh server <dataset>
    server "$@";;
  list)
    # help: \nlist: run `zfs list` remotely on backup server (ie. query the backup server from the client)
    # help:   zfsync.sh list <host> [options] <dataset>
    HOST="$1"; shift
    connect "${HOST}"
    $RPC list "$@";;
  destroy)
    # help: \ndestroy: run `zfs destroy` remotely on backup server
    # help:   zfsync.sh destroy [options] <dataset>
    HOST="$1"; shift
    connect "${HOST}"
    $RPC destroy "$@";;
  recover)
    # help: \nsend: run `zfs send` remotely on backup server (ie. to restore a snaphshot from the backup server)
    # help:   zfsync.sh recover <host> [options] <dataset>
    HOST="$1"; shift
    connect "${HOST}"
    $RPC send "$@";;
  configuser)
    # help: \nconfiguser: create zfsync user, /etc/zfsync directory, and /etc/zfsync/.ssh/id_ed25519 ssh key
    # help:   zfsync.sh configuser [username]
    restart_as_root configuser "$@"
    configuser "$@";;
  allowsend)
    # help: \nallowsend: add zfs "send,snapshot,mount" permission for zfsync user to dataset (on client machine)
    # help:   zfsync.sh allowsend <dataset> [username]
    restart_as_root allowsend "$@"
    allowsend "$@";;
  allowreceive)
    # help: \nallowreceive: add zfs "receive,mount,create" permission for zfsync user to dataset (on backup server)
    # help:   zfsync.sh allowreceive <dataset> [username]
    restart_as_root allowreceive "$@"
    allowreceive "$@";;
  showkey)
    # help: \nshow line to add to backup server authorized_keys file (run on client)
    # help:   zfsync.sh showkey <dataset> [user]
    showkey "$@";;
  *)
    error "\nfatal error: unknown command%s" "${CMD:+": \`${CMD}\`"}"
    grep '# help: ' "$0" | grep -v 'grep' | sed 's/ *# help: //g' | sed 's/\\n/\n/g';;
esac
