
## Bootstrap

This Document covers bootstrapping of machines

#### Hyper-V Setup:
- gen2
- network1: bridge
- network2: Host Only Ethernet Adapter 192.168.222.1/24

#### Preparations

boot a suitable rescue system (hetzner, systemrescuecd) on target machine. 
- use the kernel parameter net.ifnames=0 if needed 
- config network ( to an IP known to genesis)

##### SystemRescueCD
- always download newest version, as its rolling release and installing packages will have strange results without updating.
ie if you update the kernel, the current modules might get removed and it will fail to load required modules (like vfat) later on.
- boot copy to ram. 

```
setkmap
iptables -P INPUT ACCEPT
iptables -F INPUT
passwd 
# (connect via ssh)
# you may want to remove stuff from /etc/pacman.d/mirrorlist
pacman -Syu --ignore linux-lts # update the system, but ignore the kernel. update is needed as the new packages might rely on updated *.so
pacman -S gcc make parted tmux lftp vim glibc linux-headers linux-api-headers libxcrypt 
```

#### op machine 

before a new iteration: 
- update all wget links in config/Images, then
- run a random cfgen build, to update the generated DNS config (delete cache), then
- update DNS config and generate new SSL certs
- generate new deployable images
```
# in cfgen dir run
rm -rf /tmp/cfgen_cache && ./cfgen.pl build
# in dnssl run
./dnssl.pl update dns
./dnssl.pl update ssl certs 
# update repo secrets
tmux
./dnssl.pl update git secrets
rm -rf /tmp/cfgen_cache && ./cfgen.pl build build
```

in a genesis shell, set target machine:
```
# CAUTION: this destroys all data without warning.
set machine build/buildhost
bootstrap machine
```
