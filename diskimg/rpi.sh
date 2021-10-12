#!/bin/bash
# Needs root for deps and chroot and stuff
# Tested on Debian, but should work on other deb systems easily,
# and can probably be ported to other distros pretty easily

cd `dirname $0`
mkdir -p dl tmp

# Cleanup in case of failed previous run
sudo umount -q tmp

# Make sure we have all build-deps
sudo apt-get -q install \
    wget \
    zip \
    fdisk \
    binfmt-support \
    qemu-user-static
echo

# Need to restart binfmt after install of qemu for arm
sudo systemctl restart systemd-binfmt.service

# Cached download of the rpi img
cd dl
if [ ! -f 2021-05-07-raspios-buster-armhf-lite.img ]; then
    wget https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2021-05-28/2021-05-07-raspios-buster-armhf-lite.zip
    unzip 2021-05-07-raspios-buster-armhf-lite.zip
fi
cd ..

# Get some partition info from the diskimage
FDISK=$( sudo fdisk -l dl/2021-05-07-raspios-buster-armhf-lite.img -o Start )

# Determine sector size and start sector of last (main) partition --> start byte
SECTOR=$( echo "$FDISK" | grep 'Units' | cut -d' ' -f6 )
START=$( echo "$FDISK" | tail -1 )
STARTBYTE=$(($SECTOR * $START))

# Loop mount the diskimage into the temp directory
sudo mount -o loop,offset=$STARTBYTE dl/2021-05-07-raspios-buster-armhf-lite.img tmp

# Now a bunch of commands are run via chroot
CHROOT="sudo chroot tmp"

# Let's quickly check that the architecture is correct
UNAME=$( $CHROOT uname -a | grep -i arm )
if [ -z "$UNAME" ]; then
    echo "!!! Mounted diskimage is not for ARM architecture."
    echo "!!! Make sure chroot/qemu/binfmt are working, then try again."
    sudo umount -q tmp
    exit 1
fi
echo "chroot is working: $UNAME"
echo

###sudo umount -q tmp
