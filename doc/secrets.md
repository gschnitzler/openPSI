## GPG key generation and export

This is what i did to generate and export the gpg key.
Should the key ever get compromised, follow the steps below. (as root)

```
# there is some (understatement of the century) issues with gpg. it has issues with tty permissions.
# calling tmux before running the below commands fixes that.
tmux 
# accept the defaults, Real Name: 'psi-secrets'
# if there is not enough entropy, on a second terminal, run: rngd -r /dev/urandom
gpg --gen-key
gpg --export-secret-keys --armor psi-secrets > psi-secrets.gpg.priv
gpg --armor --output psi-secrets.gpg.pub --export 'psi-secrets'

#here, type 5
gpg --edit-key 'psi-secrets' trust quit

# gpg has a trustlevel, which cannot be set in batch mode on importing the keys.
# thus, this trustlevel has to be carried over.
gpg --export-ownertrust | grep $(gpg --list-keys 'psi-secrets' | grep '^ ' | sed -e 's/\s//g') > psi-secrets.gpg.trust
```

## GPG key import

If a op machine was Updated, run (as root in tmux):

```
./tools/psi-secrets.sh 
```

On new installs, the 3 files have to be copied over beforehand :)

## pass init

This was used to initialize the password store
Note that pass is controlled by environment variables, which are set during package installation.

```
pass init 'psi-secrets'
```

## batch import of secrets

```
cd $secrets_dir;
for i in $(ls); do pass insert -f -m $i < $i; done
```

