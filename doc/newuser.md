## new user

in config/Accounts/User: copy a file and change it as required
read cfgen/Plugins/Config/Accounts/Plugin.pm for how to add required keys.

- hand over the ssh private key
- hand over gauth key
- hand over ipsec keys and export password
- user has to install the google authenticator app and add his key

```
# on the servers in question, update genesis and run:
genesis clean host config
genesis generate host config all
genesis install host config
genesis add users
# reboot the machine or restart the services in question
```