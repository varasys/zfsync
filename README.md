# zfsync

## Introduction

The `zfsync` script is a bash shell script to create ZFS snapshots, and backup snapshots to a remote server over ssh.

The design goals of `zfsync` are to be extremely simple to use, and to not store any metadata in the zfs datasets. I have tried other third party zfs utilities for creating snapshots and mirroring datasets which have either stored metadata in the dataset, or created lots of holds that were either frustrating to troubleshoot when something didn't work right, or frustrating to undo when I stopped using that tool.

The `zfsync` script runs on-demand (ie. it is not a daemon) on the local computer. On the backup server the script is executed from the `ssh` authorized_keys file with the `zfsync server <dataset_root>` command (ie. it is run instead of a login shell for an incoming ssh connection). This ensures that only datasets below the <dataset_root> can be inspected/manipulated from a remote connection.

## Operation Summary

This section describes in general how `zfsync`. Refer to the Reference section below for descriptions of each subcommand, and to the man page for detailed descriptions.

In it's simplest form, the `zfsync snap` command atomically creates a set of snapshots and then a bookmark for each snapshot. Datasets with the 'com.sun:auto-prefix' user property set to 'false' will be excluded.

In it's simplest form, the `zfsync mirror` command performs a `zfs send -w` on the local computer, and a `zfs receive` on the remote backup server over a `ssh` tunnel. Note that `zfsync send -w` includes the "-w" flag which performs a "raw" send, so encrypted datasets can be sent without the decryption key ever being on the backup server. This allows secure backups on marginally trusted backup servers without the backup server ever having the backup key. The script is run on the remote backup server (ie. the receiving side) from the ssh 'authorized_keys' file to run the command `zfsync server <dataset_root>` instead of a login shell. Specifying the dataset_root ensures that the sender can only access/modify datasets under the dataset_root (and not any arbitrary dataset on the remote backup server). It is recommended to use the `zfsync configuser` command to create a dedicated 'zfsync' system user on both the sending and receiving side (and use the 'zfsync' authorized_keys file to run the `zfsync server <dataset_root>` command).

There is also a `zfsync backup` command which combines `zfsync snap` and `zfsync mirror` into a single command.

Since an offsite backup is not very useful if you can't recover it when needed, `zfsync` also provides the `zfsync list` to list datasets on the remote backup server, `zfsync recover` to recover a dataset from the remote backup server, and the `zfsync destroy` command to destroy a dataset from the backup server.

In order to enhance security, it is best to run `zfsync` on both the local and remote users with a dedicated user. The `zfsync configuser` command creates a new system user called 'zfsync' with home directory at '/usr/local/share/zfsync' and a new ssh keypair in the home directory, and symlink in the home directory from "ssh" to ".ssh" (for convenience), and an empty "authorized_keys" file. This should be run on both the local computer and remote backup server. Then on the local computer run the `zfsync allowsend <dataset>` command to delegate snapshot and send permissions to the 'zfsync' user. On the backup server run the `zfsync allowreceive <dataset> <key>` command to delegate receive permissions to the 'zfsync' user, where the <key> argument is from the output of the `zfsync allowsend` command (ie. the ssh public key of the zfsync user on the sending server).

Systemd service and timer files are included to run it as a system service periodically.

## Reference

### Snapshots and Backups

**zfssync snap** [**-r**|**-d** *depth*] *\<dataset>* ...

Create snapshot of each \<dataset\>. Specify the '-r' flag to include all child datasets, or the '-d depth' option to specify how many levels of children to include. Datasets with the 'com.sun:auto-snapshot' user property set to 'false' will not be included (see AUTOSNAPPROP environment variable below).

For each snapshot a bookmark will also be created. This allows the snapshot, which takes storage space, to be destroyed in the future, and still allow the bookmark, which does not take any storage space, to be used as the basis for an incremental send.

**zfsync mirror** *\<host\>* [**-r**|**-d** *depth*] *\<dataset\>* ...

Mirror the latest snapshot of each \<dataset\> to \<host\>. Specify the '-r' flag to include all child datasets, or the '-d depth' option to specify how many levels of children to include. Datasets with the 'com.sun:auto-snapshot' user property set to 'false' will not be included (see AUTOMIRRORPROP environment variable below).

This command will query \<host\> to see whether \<dataset\> already exists (under \<dateset_root\>), and will create it if required. Then it will perform incremental sends to transfer all snapshots from the local computer which are newer than the newest snapshot on \<host\>.

This command uses `ssh` to connect to \<host\>, and the 'authorized_keys' file on \<host\> to run `zfsync server <dataset_root>` to provide the receiving functionality. In this way, the administrator of \<host\> has control to ensure the correct version of `zfsync` is running, and can restrict the datasets which may be manipulated to only those under \<dataset_root\>.

It is recommended to use the `zfsync configuser` command (see below) to setup a dedicated user instead of running the script as root or a normal user.

There are some `ssh` options hard coded into the script for things such as multiplexing over a control master, etc. If any other connection parameters need to be set (such as the port) the best way to do it is by creating an entry for the remote backup host in the "$HOME/.ssh/config" file.

**zfsync backup** *\<host\>* [**-r**|**-d** *depth*] *\<dataset\>* ...

The backup command is just a convenience function to run `zfs snap` and then `zfs mirror`.

**zfsync server** *\<dataset_root\>*

This command is meant to be run from the 'authorized_keys' file on the backup server (see authorized_keys in sshd manpage). This allows the computer being backed up to connect with `ssh` and query, send, receive, or destroy any dataset below \<dataset_root\>.

**zfsync prune** [**-r**|**-d** *depth*] *\<dataset\>* ...

Prune old snapshots. Refer to the manpage for the retention schedule. The **-r** and **-d** arguments have the same meaning as the **zfsync snap** command.

### Interacting with the remote backup server

The following commands just forward standard zfs commands to the remote server. `zfsync` is specifically designed to backup encrypted datasets on marginally trusted third party servers, and there is no expectation that the person performing the backup has any access to the remote backup server other than through these commands. These commands should be secure because the remote backup server is configured to run from the authorized_keys file on a non-privileged user, and access to the datasets is restricted to just the children of the dataset specified in the `zfsync server <dataset>` command.

**zfsync list** *\<host\>* [options] *\<dataset\>* ...

This command executes `zfs list [options] \<dataset_root\>/\<dataset\> ...` on the remote backup server to allow the datasets on the backup server to be queried from the local computer. The options are the same options that apply to the `zfs list` command. Note that the remote backup server automatically prepends the \<dataset_root\> (from the command string in the authorized_keys file).

**zfsync destroy** *\<host\>* [options] *\<dataset\>* ...

This command executes `zfs destroy [options] \<dataset_root\>/\<dataset\> ...` on the remote backup server to allow the datasets on the backup server to be destroyed from the local computer. The options are the same options that apply to the `zfs destroy` command. Note that the remote backup server automatically prepends the \<dataset_root\> (from the command string in the authorized_keys file).

**zfsync recover** *\<host\>* [options] *\<dataset\>* ...

This command executes `zfs send [options] \<dataset_root\>/\<dataset\> ...` on the remote backup server to allow the datasets on the backup server to be recovered from the local computer (ie. disaster recovery). The options are the same options that apply to the `zfs send` command. Note that the remote backup server automatically prepends the \<dataset_root\> (from the command string in the authorized_keys file).

**zfsync rprune** [**-r**|**-d** *depth*] *\<dataset\>* ...

Prune old snapshots on the remote backup server. Refer to the manpage for the retention schedule. The **-r** and **-d** arguments have the same meaning as the **zfsync snap** command.

### User Management

For security reasons, it is best to create a dedicated non-privileged user to run the `zfsync` utility. These commands are meant to create such a user and delegate the proper privileges to them, as well as configuring `ssh` authorized_keys.

**zfsync configuser** [username] [homedir]

This command creates a dedicated system user meant to be used to for backups on both the sending computer and the remote backup server. The default user is 'zfsync' and the default home directory is '/etc/zysync'. A symlink is created from '.ssh' in the home directory to the home directory itself so `ssh` will still find the files in the users "$HOME/.ssh" folder, and they will still be visible in the "$HOME" directory (just for convenience). Also an ssh key will be generated in the home directory if it doesn't already exist.

This command may be run multiple times, and steps that have already been performed will just be skipped.

**zfsync allowsend** *\<dataset\>* [username]

This command is used on the local computer and runs `zfs allow` to delegate the required permissions to the zfsync user to be able to execute `zfs snap` and `zfs send`. The command will also print the ssh key of the zfsync user which should be input to the `zfsync allowreceive` command to update the 'authorized_keys' files on the remote backup server to allow the user to connect over `ssh`.

**zfsync allowreceive** *\<dataset\>* *\<key\>* [username]

This command is used on the remote backup server and runs `zfs allow` to delegate the required permissions to the zfsync user to be able to execute `zfs receive`. The command will update the "$HOME/.ssh/authorized_keys" file with the ssh key to run the `zfsync server <dataset>` command when the user with that key connects via `ssh`. Note that the key argument should be quoted.

## `inittest.sh`

There is a script called `inittest.sh` which creates two file based zpools (source and target) which were used during the testing and development of this script. These are included in case any users want to use it to test out `zfsync` functionality. Normally `zfsync` would be used to mirror datasets between two different hosts, but for testing and experimenting it will work with 'localhost' as the remote backup server.

## TODO

[ ] implement hooks (ie. such as a post-receive hook to allow backups to be cascaded to other backups for redundancy); this is trivial to implement, but I want to get more experience using the basic script first to make sure it meets all the basic needs
[ ] implement pruning; this is non-trivial and there are lots of different use cases (laptop => backup server wants to prune more on the backup server; but production server to backup server wants to prune more on the production server for example) - I expect this is probably best implemented in a separate script which can be called from hooks in `zfsync`
