# zfsync

## Introduction

The `zfsync` script is a bash shell script to create ZFS snapshots, and backup snapshots to a remote server over ssh.

The design goals of `zfsync` are to be extremely simple to use, and to not store any metadata in the zfs datasets. I have tried other third party zfs utilities for creating snapshots and mirroring datasets which have either stored metadata in the dataset, or created lots of holds that were either frustrating to troubleshoot when something didn't work right, or frustrating to undo when I stopped using that tool.

The `zfsync` script runs on-demand (ie. it is not a daemon) on the local computer. On the backup server the script is executed from the `ssh` authorized_keys file with the `zfsync server <dataset_root>` command (ie. it is run instead of a login shell for an incoming ssh connection). This ensures that only datasets below the <dataset_root> can be inspected/manipulated from a remote connection.

## Operation Summary

This section describes in general how `zfsync`. Refer to the Reference for a detailed description of each command.

In it's simplest form, the `zfsync snap` command atomically creates a set of snapshots and then a bookmark for each snapshot.

In it's simplest form, the `zfsync mirror` command performs a `zfs send -w` on the local computer, and a `zfs receive` on the remote backup server over a `ssh` tunnel. Note that `zfsync send -w` includes the "-w" flag which performs a "raw" send, so encrypted datasets can be sent without the decryption key ever being on the backup server. This allows secure backups on marginally trusted backup servers without the backup server ever having the backup key.

There is also a `zfsync backup` command which combines `zfsync snap` and `zfsync mirror` into a single command.

Since an offsite backup is not very useful if you can't recover it when needed, `zfsync` also provides the `zfsync list` to list datasets on the remote backup server, `zfsync recover` to recover a dataset from the remote backup server, and the `zfsync destroy` command to destroy a dataset from the backup server.

In order to enhance security, it is best to run `zfsync` on both the local and remote users with a dedicated user. The `zfsync configuser` command creates a new system user called 'zfsync' with home directory at '/etc/zfsync' and a new ssh keypair in the home directory, and symlink in the home directory from ".ssh" to "./", and an empty "authorized_keys" file. This should be run on both the local computer and remote backup server. Then on the local computer run the `zfsync allowsend` command to delegate snapshot and send permissions to the 'zfsync' user. On the backup server run the `zfsync allowreceive` command to delegate receive permissions to the 'zfsync' user. Finally, run the `zfsync showkey` command on the local computer and copy the output to the '/etc/zfsync/authorized_keys' file on the remote backup server.

Systemd service and timer files are included to run it as a system service periodically.

## Reference

### `zfsync snap`
**zfssync snap** [**-r**|**-d** *depth*] *\<dataset>* ...
Create snapshot of each <dataset>. Specify the '-r' flag to include all child datasets, or the '-d depth' option to specify how many levels of children to include. Datasets with the 'com.sun:auto-snapshot' property set to 'false' will not be included (see AUTOSNAPPROP environment variable below).

For each snapshot a bookmark will also be created. This allows the snapshot, which takes storage space, to be destroyed in the future, and still allow the bookmark, which does not take any storage space, to be used as the basis for an incremental send.

### `zfsync mirror`
**zfsync mirror** *\<host\>* [**-r**|**-d** *depth*] *\<dataset\>* ...
Mirror 
