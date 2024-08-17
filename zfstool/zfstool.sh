#!/bin/bash

# This script is designed to adhere to best practices for creating ZFS pools and datasets.
# Note: It's not advisable to rely solely on default property inheritance at the pool level.
# Instead, explicitly set properties on datasets that may serve as roots for backups.
# Note: you must have the actual encryption root dataset for every child dataset that relies on it
# (ie. backing up the child dataset without the encryption root is not useful)

# Function to create a ZFS pool
create_zpool() {
	POOL="${1:?missing pool name}"
  shift
	echo "Creating ZFS pool $POOL on $@"
	sudo zpool create \
		-o ashift=12 \
		-o autotrim=on \
		-O acltype=posixacl \
		-O mountpoint=none \
		-O compression=on \
		-O dnodesize=auto \
		-O normalization=formD \
		-O relatime=on \
		-O xattr=sa \
		"$POOL" \
		"$@"
}

# Function to create an encrypted ZFS dataset
create_encrypted_zfs() {
    echo "Creating encrypted ZFS dataset $@"
    sudo zfs create \
      -o encryption=on \
      -o keyformat=passphrase \
      -o keylocation=prompt \
      "$@"
}

COMMAND="${1:?missing command}"
shift

# Case statement to handle different symlink names
case "$COMMAND" in
    "pool")
        create_zpool "$@";;
    "encryptionroot")
        create_encrypted_zfs "$@";;
    *)
			echo "usage: $(basename $0) pool 'name' 'vdev1' 'vdev2' ..."
			echo "usage: $(basename $0) encryptionroot 'pool/dataset'"
			exit 1;;
esac
