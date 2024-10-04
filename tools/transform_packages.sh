#!/usr/bin/bash

for d in $(find . -type d| grep packages | grep -v packages/ |  sed -e 's/\/packages//'); do

cd $d;
mv packages packages_old
mkdir packages

for i in $(ls packages_old); do
	#echo $i;
	for o in $(ls packages_old/$i); do
#		echo "@$o packages/$i"
#		echo $o;
		echo "#@$o" >> packages/$i
		echo "" >> packages/$i
		cat packages_old/$i/$o >> packages/$i
		echo "" >> packages/$i
	done
	echo "====";
done

rm packages_old
cd /data/genesis/Docker/Build
done
