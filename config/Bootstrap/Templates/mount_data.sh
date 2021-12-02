#!/bin/bash
mount -o subvol=data [% machine.self.RAID.DISK1 %] [% paths.data.ROOT %]
mkdir -p [% paths.data.IMAGES %]
mkdir -p [% paths.psi.ROOT %]
