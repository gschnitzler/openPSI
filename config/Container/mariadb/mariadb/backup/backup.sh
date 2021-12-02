#!/bin/bash

# TT variables to be setup in container backup cmd
WEEKDAY=$(date +%w)
BACKUPDIR="[% container.config.CONTAINER.PATHS.BACKUP %]"
DBPW="[% container.config.OPTIONS.MARIABACKUP_PW %]"

rm -rf $BACKUPDIR/$WEEKDAY
mkdir -p $BACKUPDIR/$WEEKDAY

# create full backup
mariabackup --backup --user=mariabackup --password="$DBPW" --target_dir=$BACKUPDIR/$WEEKDAY 2>&1
# fix files
mariabackup --prepare --target_dir=$BACKUPDIR/$WEEKDAY 2>&1

