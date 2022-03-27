#!/bin/sh
set -u

echo "DESTDIR=${DESTDIR:=""}"
echo "PREFIX=${PREFIX:="/usr/local"}"

echo "BINDIR=${BINDIR:="${DESTDIR}${PREFIX}/bin"}"
echo "DOCDIR=${DOCDIR:="${DESTDIR}${PREFIX}/share/doc"}"
echo "MANDIR=${MANDIR:="${DESTDIR}${PREFIX}/share/man/man1"}"
echo "SYSTEMDDIR=${SYSTEMDDIR:="${DESTDIR}/etc/systemd/system"}"
echo

case "${1:-"install"}" in
  install)
    install -v -d "${BINDIR}"
    install -v -d "${DOCDIR}/zfsync"
    install -v -d "${MANDIR}"
    install -v -m 755 zfsync "${BINDIR}/"
    install -v zfsync.service "${SYSTEMDDIR}/"
    install -v zfsync.timer "${SYSTEMDDIR}/"
    install -v inittest.sh "${DOCDIR}/zfsync/"
    install -v README.md "${DOCDIR}/zfsync/"
    install -v install.sh "${DOCDIR}/zfsync/"
    install -v UNLICENSE "${DOCDIR}/zfsync/"
    # install -v zfsync.1 "${MANDIR}/"
    gzip  --to-stdout zfsync.1 > "${MANDIR}/zfsync.1.gz"
    printf '\nfinished installing zfsync\n\nread the man page for configuration and use instructions\n\n'
    ;;
  uninstall)
    rm -v "${BINDIR}/zfsync"
    rm -v "${SYSTEMDDIR}/zfsync.service"
    rm -v "${SYSTEMDDIR}/zfsync.timer"
    rm -v "${MANDIR}/zfsync.1.gz"
    rm -v -rf "${DOCDIR}/zfsync"
    printf '\nfinished uninstalling zfsync\n\n'
    ;;
esac
