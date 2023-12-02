#!/bin/bash

# This script is designed to adhere to best practices for creating ZFS pools and datasets.
# Note: It's not advisable to rely solely on default property inheritance at the pool level.
# Instead, explicitly set properties on datasets that may serve as roots for backups.
# This ensures that these datasets remain accessible, especially in scenarios where the encryption root is not included in the backup.


# Function to create a ZFS pool
create_zpool() {
    echo "Creating ZFS pool ..."
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
      "$@"
}

# Function to create an encrypted ZFS dataset
create_encrypted_zfs() {
    echo "Creating encrypted ZFS dataset ..."
    create_unencrypted_zfs \
      -o encryption=on \
      -o keyformat=passphrase \
      -o keylocation=prompt \
      "$@"
}

# Function to create an unencrypted ZFS dataset
create_unencrypted_zfs() {
    echo "Creating unencrypted ZFS dataset..."
    sudo zfs create \
      -o acltype=posixacl \
      -o compression=on \
      -o dnodesize=auto \
      -o normalization=formD \
      -o relatime=on \
      -o xattr=sa \
      "$@"
}

# Get the script's base name to determine the action
script_name="$(basename "$0")"

# Case statement to handle different symlink names
case "$script_name" in
    "mkfs.zpool")
        create_zpool "$@";;
    "mkfs.zfs")
        create_encrypted_zfs "$@";;
    "mkfs.zfs-clear")
        create_unencrypted_zfs "$@";;
    *)
        echo "Unknown command"
        exit 1
        ;;
esac
