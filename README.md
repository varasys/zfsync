# zfsync.sh

This script has two parts:

* `zfsync.sh init_test [clean]`: (THIS IS NOT SPLIT OUT INTO ITS OWN `inittest.sh` SCRIPT) will create two zfs zpools (source and target) with sparse files backing them, and some additional datasets in the source dataset to be used for experimenting with ZFS send/receive
* `zfsync.sh sync`: will synchronize datasets between a source and target

## Environment Variables

* `SOURCE`: the name of the source zpool (and backing file created with `zfsync.sh init_test`)
* `TARGET`: the name of the target zpool (and backing file created with `zfsync.sh init_test`)
* `DATASET`: the dataset on the source zpool to be synchronized to the target zpool
* `WORKDIR`: the directory to contain the backing files with `zfsync.sh init_test`

## Normal Use

For normal use, `SOURCE`, `TARGET` and `DATASET` should be provided as environment variables.

In the example below, 'scavenger' and 'passport' are zpool names, and 'files' is the name of the dataset on 'scavenger' to by synced to 'passport'.

``` sh
SOURCE=scavenger TARGET=passport DATASET=files zfsync.sh sync
```

## Systemd Integration

The following files are provided to integrate into systemd. Copy them to the '/etc/systemd/system/' directory and then run `sudo systemctl daemon-reload` and then `sudo systemctl enable --now zfsync.timer` to enable it, or run `systemctl start zfsync.service` to manually run it. The `zfsync.sh` script must be somewhere in the path (suggest '/usr/sbin/zfsync.sh').

Update the [OnCalendar](https://www.freedesktop.org/software/systemd/man/systemd.time.html) value in the 'zfsync.timer' file to update how often it runs.

* zfsync.service: service unit file (replace environment variables as needed)
* zfsync.timer: timer unit file to run automatically periodically

## Limitations

If a new dataset is added after the initial sync, you need to manually sync it (using `zfs send | zfs receive`) in order to get it's latest snapshot on the target to the same level as the other snapshots on the target. This is because the script uses zfs recursive functionality instead of handling each dataset individually.
