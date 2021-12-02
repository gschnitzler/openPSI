#!/bin/bash

# the 'network receiver' syslogd. directly logging to elasticsearch
# droping privs requires other ports, put syslog does not like to run as non-root

bash -c 'export LD_LIBRARY_PATH=$(find / | grep libjvm.so | sed -e "s/\/[^/]*$//"):$LD_LIBRARY_PATH && ln -fs [% container.config.CONTAINER.PATHS.CONFIG %]/syslog/ca/cacert.pem [% container.config.CONTAINER.PATHS.CONFIG %]/syslog/ca/$(cat [% container.config.CONTAINER.PATHS.CONFIG %]/syslog/ca/cacert.pem | openssl x509 -noout -hash).0'
mkdir -p [% container.config.CONTAINER.PATHS.PERSISTENT %]/logs/syslog
mkdir -p [% container.config.CONTAINER.PATHS.PERSISTENT %]/syslog/buffer
