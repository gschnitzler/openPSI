## Description

### Folders

#### cfgen
cfgen assembles 'Config' and 'secrets' and builds BTRFS images containing host specific configuration and needed genesis modules. These images are deployed to each machine.

#### dnssl
used to maintain DNS entries (cloudflare) and SSL certs (letsencrypt)

#### genesis

- './Config' contains machine specific configuration files generated by cfgen.
- './Plugins' provide all the functionality and executable commands.

#### tools
various devtools 

## From Scratch Instructions

There is currently no documentation on howto setup an environment to make use of these tools.
The lack of documentation to generate the required configuration not distributed with openPSI-config might be even more inconvenient. Finally, the complete absence of any other documentation should give a last hint: DO NOT USE THIS.

## Bootstrap Preparation

This covers bootstrapping of machines (requires op env and config)

#### Hyper-V Setup:
- gen2
- network1: bridge
- network2: Host Only Ethernet Adapter 192.168.222.1/24 (example)

#### Preparations

boot a suitable rescue system (hetzner, systemrescuecd) on target machine. 
- use the kernel parameter net.ifnames=0 if needed # on machines utilzing DHCP
- config network (to an IP known to genesis)

##### SystemRescueCD
- always download the latest version, as arch' rolling release nature will have strange results without updating.
ie if you update the kernel, the current modules might get removed and it will fail to load required modules (like vfat) later on.
- boot copy to ram. 

```
setkmap
passwd 
systemctl stop iptables
# or
iptables -P INPUT ACCEPT
iptables -F INPUT
# connect via ssh
# you may want to remove stuff from /etc/pacman.d/mirrorlist
pacman -Syu --ignore linux-lts # update the system, but ignore the kernel. update is needed as the new packages might rely on updated *.so
pacman -S gcc make glibc linux-headers linux-api-headers libxcrypt # prior to 10.0 also: parted tmux lftp vim 
```



#### op machine 

before a new iteration: 
- update all wget links in config/Images, then
- run a random cfgen build, to update the generated DNS config (delete cache), then
- update DNS config and generate new SSL certs (can be done after HostOS generation)
- generate new deployable images

```
# in cfgen dir
rm -rf /tmp/cfgen_cache && ./cfgen.pl build
# in dnssl dir
./dnssl.pl update dns 
./dnssl.pl update ssl certs # On Wait for DNS hangs, change resolv.conf to 1.1.1.1 and restart dnsmasq
tmux
./dnssl.pl update git secrets # update repo secrets
rm -rf /tmp/cfgen_cache && ./cfgen.pl build build # rebuild
# update calendar with expiry dates
```

in a genesis shell, set target machine:
```
# CAUTION: this destroys all data without warning.
set machine build/buildhost
bootstrap machine
```


## Bootstap Buildhost

First, build an image and kernel to boot into.
kernel options can be manipulated interactively. for required drivers see doc/kernel.txt.

IMPORTANT: Don't forget to check in updated kernel config

```
# test if tmux is working (close all terminals on buildhost and restart them)
cd /data/psi/genesis
./genesis.pl
# in the genesis shell
build os_base
build os_host
# attach to the tmux session via 'tmux attach -t os_host' to configure the kernel
bootstrap target system
unmount bootstrap
switch system
# system shell
reboot
# if 'reboot' fails (yes, systemd can fail to do that), use 'kill 1' and 'kill -9 1', then try again.' yeah.. i know
```


#### Building the rest

```
# genesis
build mariadb_galera
# stop any containers if necessary
docker add base
clean docker
docker save
```


## Node Update

#### update genesis

- prior to all tasks, update genesis

#### System Update

don't update (meaning reboot) all machines in a given group at once to not break (DB) clusters.
on production, also take out the node from dns and wait for all connections to cease.

```
# genesis
# for production machines, push hostos and boot images by hand
# ie with 
push normal image_hostos de-cluster2
# on stagecontrol, then, on the production machine, use
update local
# same goes for buildhost (without the prior push of course)

# for non production machines, just do
set machine build/buildhost
update system

# after any of the above steps
compare system version
# look for major version changes that would require config updates
unmount system
switch system
# reboot into updated machine
```

#### Docker Update

```
# genesis
# for production machines, push it (ie on stagecontrol)
push normal docker de-cluster2

# for non production machines
pull normal docker_all build/buildhost

# might be a good idea to stop f2b 
/etc/init.d/fail2ban stop

# might be a good idea to update container config at this point
# genesis
clean local container config
clean production container config
generate container config
install container config

# then
update docker
compare docker version
# check for serious version changes that might need updated container config
restart container
clean docker
```


