#!/bin/sh
set -u

echo "DESTDIR=${DESTDIR:=""}"

if [ -z "${DESTDIR}" ] && [ "$(id -u)" -ne 0 ]; then
  printf 'restarting as root ...\n' >&2
  exec sudo -E "$0" "$@"
fi

echo "PREFIX=${PREFIX:="/usr/local"}"

echo "BINDIR=${BINDIR:="${DESTDIR}${PREFIX}/bin"}"
echo "DOCDIR=${DOCDIR:="${DESTDIR}${PREFIX}/share/doc/zfsync"}"
echo "MANDIR=${MANDIR:="${DESTDIR}${PREFIX}/share/man/man1"}"
echo "ETCDIR=${ETCDIR:="${DESTDIR}${PREFIX}/etc/zfsync"}"
echo "SYSTEMDDIR=${SYSTEMDDIR:="${DESTDIR}/etc/systemd/system"}"
echo "COMPLETEDIR=${COMPLETEDIR:="${DESTDIR}${PREFIX}/share/bash-completion/completions"}"
echo

case "${1:-"install"}" in
  install)
    install -v -d "${BINDIR}"
    install -v -d "${DOCDIR}"
    install -v -d "${MANDIR}"
    install -v -d "${ETCDIR}"
    install -v -d "${COMPLETEDIR}"
    install -v -m 755 zfsync "${BINDIR}/"
    if [ -d "${SYSTEMDDIR}" ]; then
      install -v zfsync-snapshot.service "${SYSTEMDDIR}/"
      install -v zfsync-mirror.service "${SYSTEMDDIR}/"
      install -v zfsync-prune.service "${SYSTEMDDIR}/"
      install -v zfsync-snapshot.timer "${SYSTEMDDIR}/"
      [ -z "${DESTDIR}" ] && systemctl daemon-reload # only run if installing into current system
    fi
    install -v inittest.sh "${DOCDIR}/"
    install -v README.md "${DOCDIR}/"
    install -v install.sh "${DOCDIR}/"
    install -v UNLICENSE "${DOCDIR}/"
    install -v snapshot.conf.sample "${ETCDIR}/"
    install -v -T zfsync-completion.bash "${COMPLETEDIR}/zfsync"
    gzip  --to-stdout zfsync.1 > "${MANDIR}/zfsync.1.gz"
    "${BINDIR}/zfsync" configuser

    printf '\nfinished installing zfsync\n\nread the man page for configuration and use instructions\n\n'
    ;;
  uninstall)
    rm -v "${BINDIR}/zfsync"
    rm -v "${MANDIR}/zfsync.1.gz"
    rm -v -rf "${DOCDIR}"
    rm -v -rf "${ETCDIR}"
    rm -v "${COMPLETEDIR}/zfsync"
    if [ -d "${SYSTEMDDIR}" ]; then
      rm -v "${SYSTEMDDIR}/zfsync-snapshot.service"
      rm -v "${SYSTEMDDIR}/zfsync-mirror.service"
      rm -v "${SYSTEMDDIR}/zfsync-snapshot.timer"
      [ -z "${DESTDIR}" ] && systemctl daemon-reload # only run if installing into current system
    fi
    printf '\nfinished uninstalling zfsync\n\n'
    ;;
esac
