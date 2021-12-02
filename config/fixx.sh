#!/bin/bash

echo $1 $2;
path=$1;
subthis=$2;
subwith=$(echo $2 | sed -e 's/=/-/g');
grep -rn '.' $path | grep -v Binary | sed -e 's/:.*//'| uniq | xargs sed -i s/$subthis/$subwith/g
