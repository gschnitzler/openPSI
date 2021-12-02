#!/bin/bash

echo $1, $2;
grep -rn "$1" | sed -e 's/:.*//' | uniq | xargs sed -i "s/$1/$2/g"

