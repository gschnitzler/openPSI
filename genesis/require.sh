#!/bin/bash

###
### These modules are the minimal requirements to run genesis on the buildserver
### Modules required by other Plugins are installed in the os_base image 
###
export PERL_MM_USE_DEFAULT=1
export PERL_EXTUTILS_AUTOINSTALL="--defaultdeps"

# idiots added 'pushy_https' in 2021 (a little late, mind you, but ok), and made it default to true straight away. Problem?
# perl lacks tls support without modules from cpan...
# i'd argue its the same poor kids that got a copy of mastering regular expressions and made bold assumptions of what valid dns should look like.
# fucking hell
find /usr/ -type f | grep CPAN/FirstTime.pm | xargs sed -i 's/\("pushy_https" => \)1/\10/'

# gentoo seems to have fucked up. perl @INC paths are missing. cpan then defaults to install into home.
perl -V 2>&1| sed -e 's/\s*//' | grep '^/' | grep -v etc | xargs mkdir -p

# sysrescuecd does not have cpan in path
CPANLINK="$(which cpan)";
if [ "$CPANLINK" == "" ]; then
        CPANLINK=$(find /usr/bin | grep cpan- | head -n 1);
        ln -sf $CPANLINK /usr/bin/cpan
fi

# cpanm is faster, less noisy and checks if modules are already uptodate
cpan install App::cpanminus

CPANMLINK="$(which cpanm)"
if [ "$CPANMLINK" == "" ]; then
	CPANMLINK=$(find /usr/ -type f | grep cpanm$ | head -n 1)
	ln -sf $CPANMLINK /usr/bin/cpanm
fi

# legacy. should be dropped in favor of system cp
modules+=" File::Copy::Recursive"

# IO::Prompter works 'much better' with this, says conway
modules+=" Term::ReadKey"

# used as shell
modules+=" IO::Prompter"

# used for configfiles
modules+=" Template"

# postderef requires experimental
modules+=" experimental"

# PerlBestPractises
modules+=" Readonly"

# used for container start/stop
# dont run the tests, they take super long and do stupid stuff like connecting to the local ssh server.
# however, you can not turn off all tests. the ssh test continues. circumvent by not allowing ssh connects
if [ "$(which iptables)" != "" ]; then 
	ip6tables -A INPUT -p tcp -d ::1 --dport 22 -j REJECT
	iptables -A INPUT -p tcp -d 127.0.0.1 --dport 22 -j REJECT
fi
modules+=" Proc::ProcessTable"

$CPANMLINK $modules;
$CPANMLINK -nf Forks::Super --verbose # verbose to not hit a 60s comile timeout. idk... whatever


# dont carry the cruft along
rm -rf /root/.cpan
rm -rf /root/.cpanm

# hetzners rescuecd lacks tmux,
# but ignore the output as the chroot does not have it either yet
if [ "$(which tmux)" == "" ]; then 
	apt-get install tmux >/dev/null 2>&1
fi

