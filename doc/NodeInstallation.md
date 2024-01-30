
## Node Initial Installation

- a new node needs a cluster configfile first
- setup all the required certs and credentials, backup, users etc
- in hetzner robot, activate backup space if required

#### HostOS Installation

Follow Bootstrap.md, then, on the machine in question

```
# genesis
set source build/buildhost # or any machine that holds images this node knows about
bootstrap node
unmount bootstrap
switch system
# reboot
```

OR, on production machines, do

```
# on stagecontrol
push bootstrap image_hostos de-cluster1/dec1n01
# on the machine
bootstrap target system
unmount bootstrap
switch system
# reboot
```

then follow the node update instructions for installing docker.
be sure to start up the containers once for all directories to be created.
A Reboot is advised now. to ensure normal operations (some services like csync/lsync etc will not work unless restarted)

