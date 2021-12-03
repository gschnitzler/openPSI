
## Bootstrap

This Document covers bootstrapping of machines

#### Hyper-V Setup:
- gen2

#### VirtualBox Setup:

- Chipset: ICH9
- IO-APIC
- all Cores
- PAE/NX
- VT-x/AMD-V
- disks: 2x10gb SATA/AHCI or 1x15gb
- network1: bridge
- network2: Virtualbox Host Only Ethernet Adapter 192.168.222.1/24

#### Bare Metal:

- Hetzner PX60-SSD (2015), PX61-SSD (2016), PX61-NVMe (2017) and AX160-NVMe (2018) machines are supported. Similar machines might work as well.

#### Preparations

- boot a suitable rescue system on target machine. actually not that easy. 
systemrescuecd got rebased on arch. it somehow misses basic header files like sys/types.h and i couldn't find its package.
compiling prerequisits on gentoo minimal seemed overkill.
knoppix does not like hyperv and just shuts down
grml has a gcc quirk. package is installed but not found.
debian live lacks everything needed out of the box and is just a pain to use.
slax got rebased on debian and is just the wrong tool for the job
archie could not install packages because its root fs was too small
manjaro architect. does the job:

pacman -Sy && pacman -S gcc make parted tmux lftp # you may want to remove stuff from /etc/pacman.d/mirrorlist
systemctl restart sshd

- use the kernel parameter net.ifnames=0 with systemrescuecd
- set password with 'passwd'
- config network ( to an IP known to genesis)

#### op machine 

before a new iteration, update all wget links in config/Images
then, run a random cfgen build, to update the generated DNS config (delete cache)
then, update DNS config and generate new SSL certs
```
# in cfgen dir run
rm -rf /tmp/cfgen_cache && ./cfgen.pl build
# in dnssl run
./dnssl.pl update dns
./dnssl.pl update ssl certs 
```

This prepares a machine for executing genesis:

```
# to generate new deployable images
# this also generates the config for dnssl, which you might run later
rm -rf /tmp/cfgen_cache && ./cfgen.pl build build
# in a genesis shell, set target machine
set machine build/buildhost
# CAUTION: this command destroys all data without warning
# Hetzner: close all open sessions before executing this command (tmux installation)
bootstrap machine
```
