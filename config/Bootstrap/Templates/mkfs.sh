#!/bin/bash

#/dev/sda1 	(bootloader) 	2M 		BIOS boot partition
#/dev/sda2 	fat32 		128M 		Boot/EFI system partition (for future use)
#/dev/sda3 	btrfs 		Rest 		Root partition 
# only sda3 need to be formatted for the time being
# this partition scheme is hardcoded. the 3 for the root partition (the only one cared about so far) is added in various places.
# the reintroduction of partitions means that support for nvme drives is dropped, as they require an additional 'p' before the '3'.
# FML.



echo "partition disk1: "
# use gpt and Mib
parted -s -a optimal [% machine.self.RAID.DISK1 %] mklabel gpt > /dev/null
parted -s -a optimal [% machine.self.RAID.DISK1 %] unit mib > /dev/null
# bios boot partition
parted -s -a optimal [% machine.self.RAID.DISK1 %] mkpart primary 1 3  > /dev/null
parted -s -a optimal [% machine.self.RAID.DISK1 %] name 1 grub > /dev/null
parted -s -a optimal [% machine.self.RAID.DISK1 %] set 1 bios_grub on > /dev/null
# efi boot partition for later use
parted -s -a optimal [% machine.self.RAID.DISK1 %] mkpart primary 3 131 > /dev/null
parted -s -a optimal [% machine.self.RAID.DISK1 %] name 2 boot > /dev/null
parted -s -a optimal [% machine.self.RAID.DISK1 %] set 2 boot on > /dev/null
# system
parted -s -a optimal [% machine.self.RAID.DISK1 %] mkpart primary 131 100% > /dev/null
parted -s -a optimal [% machine.self.RAID.DISK1 %] name 3 rootfs > /dev/null

[% IF machine.self.RAID.LEVEL != 'raidS' %]
# only do that in raidmodes
echo "partition disk2: "
# use gpt and Mib
parted -s -a optimal [% machine.self.RAID.DISK2 %] mklabel gpt > /dev/null
parted -s -a optimal [% machine.self.RAID.DISK2 %] unit mib > /dev/null
# bios boot partition
parted -s -a optimal [% machine.self.RAID.DISK2 %] mkpart primary 1 3  > /dev/null
parted -s -a optimal [% machine.self.RAID.DISK2 %] name 1 grub > /dev/null
parted -s -a optimal [% machine.self.RAID.DISK2 %] set 1 bios_grub on > /dev/null
# efi boot partition for later use
parted -s -a optimal [% machine.self.RAID.DISK2 %] mkpart primary 3 131 > /dev/null
parted -s -a optimal [% machine.self.RAID.DISK2 %] name 2 boot > /dev/null
parted -s -a optimal [% machine.self.RAID.DISK2 %] set 2 boot on > /dev/null
# system
parted -s -a optimal [% machine.self.RAID.DISK2 %] mkpart primary 131 100% > /dev/null
parted -s -a optimal [% machine.self.RAID.DISK2 %] name 3 rootfs > /dev/null
[% END %]

echo "creating filesystems: "
mkdir -p [% paths.hostos.MOUNT %]
mkfs.btrfs -f -L disk1 [% machine.self.RAID.DISK1 %][% 'p' IF machine.self.RAID.DISK1.match('nvme') %]3 > /dev/null
mount  [% machine.self.RAID.DISK1 %][% 'p' IF machine.self.RAID.DISK1.match('nvme') %]3 [% paths.hostos.MOUNT %]

[% IF machine.self.RAID.LEVEL != 'raidS' %]
# only do that in raidmodes
btrfs device add -f [% machine.self.RAID.DISK2 %][% 'p' IF machine.self.RAID.DISK1.match('nvme') %]3 [% paths.hostos.MOUNT %]
btrfs balance start -f -dconvert=[% machine.self.RAID.LEVEL %] -mconvert=[% machine.self.RAID.LEVEL %] [% paths.hostos.MOUNT %]
[% END %]

#btrfs subvolume create [% paths.hostos.MOUNT %]/boot
mkfs.vfat [% machine.self.RAID.DISK1 %][% 'p' IF machine.self.RAID.DISK1.match('nvme') %]2
[% IF machine.self.RAID.LEVEL != 'raidS' %]
mkfs.vfat [% machine.self.RAID.DISK2 %][% 'p' IF machine.self.RAID.DISK2.match('nvme') %]2
[% END %]
btrfs subvolume create [% paths.hostos.MOUNT %]/system1
btrfs subvolume create [% paths.hostos.MOUNT %]/system2
btrfs subvolume create [% paths.hostos.MOUNT %]/data
cd / && umount -lf [% paths.hostos.MOUNT %]
