## Cluster Setup

#### 1st time db cluster setup

- make sure the config is in place and valid on all nodes
- write down the startup command (from supervisord)

to start up all the nodes manually and initialize database:


```
# copy a portage image over to the db cluster container
genesis stop container mariadb
genesis start container mariadb /usr/bin/bash
docker attach mariadb
# disable CoW for the database, note that this only takes effect for files that are CREATED AFTER chattr
mkdir /data/pdata/db && chattr +C /data/pdata/db/
# extract the portage image, then
# ignore that the database can not be started
emerge --config dev-db/mariadb
# ignore this if the container image is already bootstrapped and the container config is in place
mv /var/lib/mysql/* /data/pdata/db/
# ignore this if container is already bootstrapped
rm -rf /etc/mysql/
# ignore this also
ln -s /data/config/mysql /etc
```

- repeat on every node
- now ONLY on the FIRST node:

open /data/config/mysql/my.cnf and comment all the ^wsrep lines
then:


```

bash -c '/usr/bin/mkdir -p /var/run/mysqld && chown mysql.mysql /var/run/mysqld && exec /usr/bin/mysqld  --defaults-file="/data/config/mysql/my.cnf" --wait_timeout=1000 --log-basename=mariadb_node' &
mysql -p #password is empty
DELETE FROM mysql.user WHERE user='';
# the config script added the containers hostname for root, remove them
select Host from mysql.user where User='root';
DELETE FROM mysql.user WHERE user='root';# and Host='<thehost>';
GRANT ALL ON *.* TO 'root'@'%' IDENTIFIED BY '<thepass>' WITH GRANT OPTION;
GRANT USAGE ON *.* to cluster_sst@'localhost' IDENTIFIED BY '<thepassfromconfig>';
GRANT ALL PRIVILEGES on *.* to cluster_sst@'localhost';
FLUSH PRIVILEGES;
# uncomment the wsrep lines in config
```

kill the mysqld on the node, but don't exit the container yet.
then proceed with the next step


#### Cluster start

- assuming you just did the steps above, but every cold start of the cluster looks the same
- now on the first node, still inside the docker container, run the startup cmd and append --wsrep-new-cluster

```
bash -c '/usr/bin/mkdir -p /var/run/mysqld && chown mysql.mysql /var/run/mysqld && exec /usr/bin/mysqld  --defaults-file="/data/config/mysql/my.cnf" --wait_timeout=1000 --log-basename=mariadb_node --wsrep-new-cluster' &
tail -f -n100 /data/pdata/db/mariadb_node.err
```

start the other containers normally, or, for debugging, inside the container run

```
bash -c '/usr/bin/mkdir -p /var/run/mysqld && chown mysql.mysql /var/run/mysqld && exec /usr/bin/mysqld  --defaults-file="/data/config/mysql/my.cnf" --wait_timeout=1000 --log-basename=mariadb_node' &
tail -f -n100 /data/pdata/db/mariadb_node.err
``` 

they should join the cluster. if not, the container will exit after ~1min.
if everything seems fine, restart the container on the first node normally

