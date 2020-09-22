# zfsync.sh

This script has two parts:

* `zfsync.sh init_test [clean]`: will create two zfs zpools (source and target) with sparse files backing them, and some additional datasets in the source dataset to be used for experimenting with ZFS send/receive
* `zfsync.sh sync`: will synchronize datasets between a source and target

## Envirenment Variables

* `SOURCE`: the name of the source zpool (and backing file created with `zfsync.sh init_test`)
* `TARGET`: the name of the target zpool (and backing file created with `zfsync.sh init_test`)
* `DATASET`: the dataset on the source zpool to be syncronized to the target zpool
* `WORKDIR`: the directory to contain the backing files with `zfsync.sh init_test`

## Normal Use

For normal use, `SOURCE` and `TARGET` should be provided as environment variables.

``` sh
SOURCE=scavenger TARGET=passport DATASET=files zfsync.sh sync
```

## Systemd Integration

The following files are provided to integrate into systemd:

* zfsync.service: service unit file (replace environment variables as needed)
* zfsync.timer: timer unit file to run automatically periodically

## Limitations

If a new dataset is added after the initial sync, you need to manually sync it (using `zfs send | zfs receive`) in order to get it's latest snapshot on the target to the same level as the other snapshots on the target. This is because the script uses zfs recursive functionality instead of handling each dataset individually.
