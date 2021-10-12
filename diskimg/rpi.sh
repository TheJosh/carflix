#!/bin/bash
# Needs root for deps and chroot and stuff
# Tested on Debian, but should work on other deb systems easily,
# and can probably be ported to other distros pretty easily

set -e
cd `dirname $0`

mkdir -p dl tmp

# Cleanup in case of failed previous run
sudo umount -q tmp
rm dl/2021-05-07-raspios-buster-armhf-lite.img

# Make sure we have all build-deps
sudo apt-get -q install \
    wget zip \
    fdisk parted mount \
    binfmt-support qemu-user-static
echo

# Need to restart binfmt after install of qemu for arm
sudo systemctl restart systemd-binfmt.service

# Cached download of the rpi img
cd dl
if [ ! -f 2021-05-07-raspios-buster-armhf-lite.zip ]; then
    wget https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2021-05-28/2021-05-07-raspios-buster-armhf-lite.zip
fi
unzip 2021-05-07-raspios-buster-armhf-lite.zip
cd ..
DISKIMG="dl/2021-05-07-raspios-buster-armhf-lite.img"

# Grow diskimage by 64M so we've got enough space for packages etc
# Grow partition 2 to use the extra space
dd if=/dev/zero bs=1M count=64 >> "$DISKIMG"
sudo parted "$DISKIMG" resizepart 2

# Get some partition info from the diskimage
FDISK=$( sudo fdisk -l "$DISKIMG" -o Start )

# Determine sector size and start sector of last (main) partition --> start byte
SECTOR=$( echo "$FDISK" | grep 'Units' | cut -d' ' -f6 )
START=$( echo "$FDISK" | tail -1 )
STARTBYTE=$(($SECTOR * $START))

# Loop mount the diskimage into the temp directory
sudo mount -o loop,offset=$STARTBYTE "$DISKIMG" tmp

# We grew the partion previously; need to expand filesystem too
LOOPDEV=$( sudo losetup --list | grep "$DISKIMG" | cut -d' ' -f1 )
sudo resize2fs $LOOPDEV

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

# Copy over the app
echo "Installing app into /home/pi/carflix"
mkdir -p tmp/home/pi/carflix
cp -r ../app tmp/home/pi/carflix
cp -r ../assets tmp/home/pi/carflix
cp -r ../vendor tmp/home/pi/carflix
cp ../* tmp/home/pi/carflix 2>/dev/null || :
chown 1000:1000 -R tmp/home/pi/carflix

# Install dependencies
$CHROOT apt-get  -y update
$CHROOT apt-get -y install golang ffmpeg

###sudo umount -q tmp
