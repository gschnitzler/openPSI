#!/bin/bash
#
# ONLY RUN THIS IN TMUX
#

gpg --allow-secret-key-import --import /data/psi-secrets.gpg.priv > /dev/null 2>&1
gpg --import /data/psi-secrets.gpg.pub > /dev/null 2>&1
gpg --import-ownertrust /data/psi-secrets.gpg.trust > /dev/null 2>&1
mkdir -p /root/.password-store
ln -s /data/psi/config-private/Secrets/ /root/.password-store/psi-secrets

# patch pass to disabe git.
# pass wants to git commit if it finds a git repo in the parent dirs, and there is no way of disabling that. 
sed -i 's/\(set_git\s\)/set_git2 /' /usr/bin/pass
sed -i '2iset_git2() { true; }' /usr/bin/pass

