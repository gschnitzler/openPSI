#!/bin/bash
echo "creating filesystems: "
mkfs.btrfs -f -L disk1 [% machine.self.RAID.DISK1 %] > /dev/null
mount  [% machine.self.RAID.DISK1 %] [% paths.hostos.MOUNT %]
[% IF machine.self.RAID.LEVEL != 'raidS' %]
# only do that in raidmodes
btrfs device add -f [% machine.self.RAID.DISK2 %] [% paths.hostos.MOUNT %]
btrfs balance start -f -dconvert=[% machine.self.RAID.LEVEL %] -mconvert=[% machine.self.RAID.LEVEL %] [% paths.hostos.MOUNT %]
[% END %]
btrfs subvolume create [% paths.hostos.MOUNT %]/boot
btrfs subvolume create [% paths.hostos.MOUNT %]/system1
btrfs subvolume create [% paths.hostos.MOUNT %]/system2
btrfs subvolume create [% paths.hostos.MOUNT %]/data
cd / && umount -lf [% paths.hostos.MOUNT %]
