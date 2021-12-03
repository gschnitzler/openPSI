
## Bootstrap

This Document covers bootstrapping of machines

#### Hyper-V Setup:
- gen2
- network1: bridge
- network2: Host Only Ethernet Adapter 192.168.222.1/24

#### Bare Metal:

EFI capable machines

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

systemrescue boot copy to ram. always download newest version, as its rolling release and installing packages will have strange results without updating.
ie if you update the kernel, the current modules might get removed and it will fail to load required modules (like vfat) later on.

iptables -P INPUT ACCEPT

iptables -F INPUT

passwd 

(connect via ssh)

# you may want to remove stuff from /etc/pacman.d/mirrorlist
pacman -Syu --ignore linux-lts # update the system, but ignore the kernel. update is needed as the new packages might rely on updated *.so
pacman -S gcc make parted tmux lftp vim glibc linux-headers linux-api-headers libxcrypt 


- use the kernel parameter net.ifnames=0 with systemrescuecd (outdated) 
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
# update repo secrets
tmux
./dnssl.pl update git secrets
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
