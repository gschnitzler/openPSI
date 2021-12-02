
## Hostbuilder Creation

Follow this document after machine bootstrapping

#### Hetzners rescuecd current issues. 

before anything, do:
```
mount -t devpts -o gid=5 pts /dev/pts/ # required for glibc updates
mount -n -t tmpfs -o noexec,nosuid,nodev,mode=1777 shm-tmpfs /dev/shm # required for python updates
```

First, we want to build an image and kernel we can boot into.
kernel options can be manipulated interactively. for required drivers see doc/kernel.txt.
IMPORTANT: copy updated kernel configuration from /root back to devop.
```
# test if tmux is working (close all terminals on buildhost and restart them)
cd /data/psi/genesis
./genesis.pl
build os_base
# now, open up a new terminal and start tmux. if it starts, exit again.
# then continue on that terminal. (this is a workaround, something is broken @hetzner)
build os_host
# attach to the tmux session via 'tmux attach -t os_host' to configure the kernel
bootstrap target system
unmount bootstrap
reboot
# if 'reboot' fails (yes, systemd can fail to do that), use 'kill 1' and 'kill -9 1', then try again.'
# yeah.. i know
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
