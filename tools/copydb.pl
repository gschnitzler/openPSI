#!/usr/bin/perl

use 5.020;
use strict;
use warnings;
use mro ();
use feature qw(signatures);
use experimental qw(postderef);


# mysqldump -p psapp_feature4 > dump.sql
# ./cleandb.pl dump.sql
# mysql -p psapp_feature5 < dump.sql

# binary version of the above:
## sadly, this does not work because of foreign keys.

# newdb must already be existing (create database $newdb)
#my $newdb     = "psapp_feature5";
#my $newdb_dir = "/data/pdata/db/psapp_feature5/";
#my $olddb     = "psapp_feature4";
#my $olddb_dir = "/data/sdata/";

#system "cd $olddb_dir && mysqldump -p --no-data $olddb > /tmp/$olddb.schema.sql";
#system "mysql -p $newdb < /tmp/$olddb.schema.sql";
#system "export innodb_import_table_from_xtrabackup=1 && innobackupex --apply-log --export $olddb_dir";
#system "mysql -N -B -p <<'EOF' > /tmp/discard-ddl.sql\
#SELECT CONCAT('ALTER TABLE ', table_name, ' DISCARD TABLESPACE;') AS _ddl\
#FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='$olddb' AND ENGINE='InnoDB';\
#EOF\
#";
#system "mysql -p $newdb < /tmp/discard-ddl.sql";
#system "cp -fp $olddb_dir/*[.exp|.ibd] $newdb_dir/";
#system "chown -R mysql.mysql $newdb_dir";
#system "mysql -N -B -p <<'EOF' > /tmp/import-ddl.sql\
#SELECT CONCAT('ALTER TABLE ', table_name, ' IMPORT TABLESPACE;') AS _ddl\
#FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='$olddb' AND ENGINE='InnoDB';\
#EOF\
#";
#system "mysql -p $newdb < /tmp/import-ddl.sql";
