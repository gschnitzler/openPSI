#!/bin/bash

# the /opt/logstash/data/queue directory is checked for write permissions. this is a bug, see
# https://github.com/elastic/logstash/issues/6378
# remove this when done


mkdir -p [% container.config.CONTAINER.PATHS.PERSISTENT %]/logstash/queue && \
chown -R logstash.logstash [% container.config.CONTAINER.PATHS.PERSISTENT %]/logstash && \
mkdir -p [% container.config.CONTAINER.PATHS.PERSISTENT %]/logs/logstash && \
chown -R logstash.logstash [% container.config.CONTAINER.PATHS.PERSISTENT %]/logs/logstash && \
export LS_HEAP_SIZE="500m" && \
export LS_JAVA_OPTS="-Djava.io.tmpdir=[% container.config.CONTAINER.PATHS.PERSISTENT %]/logstash" && \
export LS_USE_GC_LOGGING="true" && \
exec su -p -s /bin/bash -c "/opt/logstash/bin/logstash --path.config [% container.config.CONTAINER.PATHS.CONFIG %]/logstash --path.logs [% container.config.CONTAINER.PATHS.PERSISTENT %]/logs/logstash --path.data [% container.config.CONTAINER.PATHS.PERSISTENT %]/logstash" logstash

