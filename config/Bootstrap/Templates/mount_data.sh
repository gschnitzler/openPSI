#!/bin/bash
mount -o subvol=data [% machine.self.RAID.DISK1 %][% 'p' IF machine.self.RAID.DISK1.match('nvme') %]3 [% paths.data.ROOT %]
mkdir -p [% paths.data.IMAGES %]
mkdir -p [% paths.psi.ROOT %]
