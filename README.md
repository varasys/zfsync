# zfsync.sh

The `zfsync.sh` script is a posix sh shell script to create ZFS snapshots, and backup snapshots to a remote server over ssh.

Systemd service and timer files are included to run it as a system service.

## Creating Snapshots

`zfsync.sh snap <root>`

Use the command above to create a snapshot of the <root> dataset and all it's descendants. To exclude a dataset set the 'com.sun:auto-snapshot' user property to false.

## Notes

