#!/bin/bash
sourcedir=$(dirname $(realpath build.sh))
cd $sourcedir || {
    echo "cannot change dir to $sourcedir"
    exit 1
}
/bin/rm -fr ~/rpmbuild/*
cp -r * ~/rpmbuild/
cd ~/rpmbuild/SOURCES
chmod +x clear-disk-1.0/bin/*
tar czf clear-disk-1.0.tar.gz clear-disk-1.0
cd ..
rpmbuild -bb SPECS/clear-disk.spec
