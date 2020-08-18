#!/bin/bash
shopt -s extglob
buildroot=clear-disk-1.0
name=clear-disk
clean() {
    /bin/rm -fr $buildroot
    /bin/rm -f $name-*.rpm $buildroot.tar.gz
}
# build
clean
mkdir $buildroot
cp -r !($buildroot) $buildroot
rm -f $buildroot/{build.sh,*.log}
# custom actions here
chmod +x $buildroot/bin/*

tar czf $buildroot.tar.gz $buildroot
rpmbuild -tb $buildroot.tar.gz
clean
/bin/cp ~/rpmbuild/RPMS/noarch/$name-*.rpm .
