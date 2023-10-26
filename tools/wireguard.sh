#!/bin/bash

cluster_dir="/data/openPSI/openPSI-config-dotz/Cluster/"
user_dir="/data/openPSI/openPSI-config-dotz/Accounts/User"

# generate host keys 
for file in $(find $cluster_dir -mindepth 2 -type f| grep cfgen$); do

	group=$(grep GROUP $file | sed -e "s/.*'\(.*\)'.*/\1/")
	name=$(grep SHORT $file | sed -e "s/.*'\(.*\)'.*/\1/")
	$(umask 077; wg genkey | tee wireguard.host.$group.$name.key.priv | wg pubkey > wireguard.host.$group.$name.key.pub)
done

# generate user keys 
for file in $(find $user_dir -type f| grep cfgen$); do

	name=$(grep NAME $file | sed -e "s/.*'\(.*\)'.*/\1/")
	$(umask 077; wg genkey | tee wireguard.user.$name.key.priv | wg pubkey > wireguard.user.$name.key.pub)
done
