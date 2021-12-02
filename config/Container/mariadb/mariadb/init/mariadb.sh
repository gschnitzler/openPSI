#!/bin/bash

# the sed below got introduced, because of a bug. remove this once the bug is resolved
# https://bugs.gentoo.org/show_bug.cgi?id=649902
# they said its a duplicate, but i do not see the relation.
# anyway in the attached files in jira i could not find --defaults-file
# so it might be fixed by 10.1.32
# the sed fix seems not to clash. remove the line somewhen in the future after 10.1.32.
#sed -i 's/--defaults-file=//' /usr/bin/wsrep_sst_xtrabackup-v2
mkdir -p /var/run/mysqld
chown mysql.mysql /var/run/mysqld
mkdir -p [% container.config.CONTAINER.PATHS.PERSISTENT %]/tmp




