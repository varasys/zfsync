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
echo "SYSTEMDDIR=${SYSTEMDDIR:="${DESTDIR}${PREFIX}/lib/systemd/system"}"
echo "COMPLETEDIR=${COMPLETEDIR:="${DESTDIR}${PREFIX}/share/bash-completion/completions"}"
echo

case "${1:-"install"}" in
  install)
    install -v -m 755 -D -t "${BINDIR}/" zfsync
		install -v -D -t "${SYSTEMDDIR}/" zfsync-snapshot.service
		install -v -D -t "${SYSTEMDDIR}/" zfsync-mirror.service
		install -v -D -t "${SYSTEMDDIR}/" zfsync-prune.service
		install -v -D -t "${SYSTEMDDIR}/" zfsync-snapshot.timer
    install -v -D -t "${DOCDIR}/" inittest.sh
    install -v -D -t "${DOCDIR}/" README.md
    install -v -D -t "${DOCDIR}/" install.sh
    install -v -D -t "${DOCDIR}/" UNLICENSE
    install -v -D -t "${ETCDIR}/" snapshot.conf.sample
    install -v -D -t "${COMPLETEDIR}/zfsync" zfsync-completion.bash
    install -v -d "${MANDIR}"
    gzip --to-stdout zfsync.1 > "${MANDIR}/zfsync.1.gz"
    "${BINDIR}/zfsync" configuser

    printf '\nfinished installing zfsync\n\nread the man page for configuration and use instructions\n\n'
    printf '\nrun `systemctl daemon-reload`\n\n'
    ;;
  uninstall)
		systemctl disable --now zfsync-snapshot.service || :
		systemctl disable --now zfsync-mirror.service || :
		systemctl disable --now zfsync-snapshot.timer || :
    rm -v "${BINDIR}/zfsync"
    rm -v "${MANDIR}/zfsync.1.gz"
    rm -v -rf "${DOCDIR}"
    rm -v -rf "${ETCDIR}"
    rm -v "${COMPLETEDIR}/zfsync"
		rm -v "${SYSTEMDDIR}/zfsync-snapshot.service"
		rm -v "${SYSTEMDDIR}/zfsync-mirror.service"
		rm -v "${SYSTEMDDIR}/zfsync-snapshot.timer"
    printf '\nfinished uninstalling zfsync\n\n'
    ;;
esac
