
## Bootstrap

This Document covers bootstrapping of machines

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

- boot a rescue system on target machine (tested are systemrescuecd and hetzner)
- use the kernel parameter net.ifnames=0 with systemrescuecd
- set password with 'passwd'
- config network ( to an IP known to genesis)
- make sure the disks are clean (they must not contain a partition)

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
