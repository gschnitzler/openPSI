
## Node Update

#### update genesis

- prior to all tasks, update genesis

#### System Update

don't update (meaning reboot) all machines in a given group at once to not break the db cluster.
on production, also take out the node from dns and wait for all connections to cease.

```
# genesis
# for production machines, push hostos and boot images by hand
# ie with 
push normal image_hostos de-cluster2
push normal image_boot de-cluster2
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


