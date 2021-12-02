#!/bin/bash

host="[% machine.self.COMPONENTS.SERVICE.backup.TARGET %]"
user="[% machine.self.COMPONENTS.SERVICE.backup.TARGET_USER %]"
export SSHPASS="[% machine.self.COMPONENTS.SERVICE.backup.TARGET_PASSWORD %]"
echo "Setup offsite backup..."

# push pub key to server
# for initial setup, .ssh needs to be created. however if it exists (node update), it fails, thus this shellscript.
# in recent sshpass versions, -p is broken, resorted to -e, thus the export of SSHPASS
echo nameserver 8.8.8.8 >> /etc/resolv.conf # host dnsmasq not setup yet
ssh-keyscan $host 2>&1 | grep -v '^#' > /root/.ssh/known_hosts
echo -e "mkdir .ssh \n chmod 700.ssh \n" | sshpass -e sftp $user@$host > /dev/null 2>&1
echo rm .ssh/authorized_keys | sshpass -e sftp $user@$host > /dev/null 2>&1
sshpass -e scp /root/backup_ssh_pub $user@$host:.ssh/authorized_keys
echo chmod 600.ssh/authorized_keys | sshpass -e sftp $user@$host > /dev/null 2>&1
rm -f /root/backup_ssh_pub

# init remote repo. only do this, if it was not done before. that would be manual intervention territory
echo "mkdir backup" > /tmp/batch
sftp -b /tmp/batch -i /root/.ssh/backup $user@$host > /dev/null 2>&1

if [ $? == 0 ]; then
mkdir -p /tmp/backup
cat << "EOF" | base64 -d | tar -C /tmp/backup -zx
[% machine.self.COMPONENTS.SERVICE.backup.BORG_REPO %]
EOF
scp -i /root/.ssh/backup -r /tmp/backup $user@$host:
rm -rf /tmp/backup
fi

rm -f /tmp/batch
sed -i 's/.*8.8.8.8.*//' /etc/resolv.conf

# and we need a cronjob to run
echo '#!/bin/bash'          > /etc/cron.daily/backup
echo 'export HOME=/root'    >> /etc/cron.daily/backup # home is needed, otherwise ssh wont find its known host
echo genesis backup now     >> /etc/cron.daily/backup
chmod u+x /etc/cron.daily/backup

