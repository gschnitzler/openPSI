#!/bin/sh

# create a local repo, export the key and repo
# borg idiots only allow init with a key generated on spot. so pack it and deploy it as well
echo "use this for new node installations. just copy into secret files"
export BORG_BASE_DIR=/tmp/borg
export BORG_PASSPHRASE=; #used to null passphrase in init repo
repo_dir=/tmp/backup
repo_key=/tmp/key
#repo_file=/tmp/repo
mkdir -p $repo_dir $BORG_BASE_DIR
rm -rf $repo_dir/* $BORG_BASE_DIR/* $repo_key # just in case
borg init --encryption=keyfile $repo_dir > /dev/null 2>&1
borg key export $repo_dir $repo_key
echo "############ REPO KEY ###############"
cat $repo_key
echo
echo "############ REPO#####################"
cd $repo_dir && tar -C . -cJ . | base64 #> $repo_file
rm -rf $repo_dir $BORG_BASE_DIR $rep_key
echo


