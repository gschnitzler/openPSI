
## Hostbuilder Creation

Follow this document after machine bootstrapping

First, we want to build an image and kernel we can boot into.
kernel options can be manipulated interactively. for required drivers see doc/kernel.txt.
IMPORTANT: Don't forget to check in updated kernel config
```
# test if tmux is working (close all terminals on buildhost and restart them)
cd /data/psi/genesis
./genesis.pl
build os_base
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
