#!/bin/bash
# Needs root for deps and chroot and stuff
# Tested on Debian, but should work on other deb systems easily,
# and can probably be ported to other distros pretty easily

set -e
cd `dirname $0`

info () {
    echo -e "\033[1;33m${1}\033[0m"
}

# Basic setup + cleanup in case of failed previous run
mkdir -p dl tmp
sudo umount -q tmp || :
rm -f dl/2021-05-07-raspios-buster-armhf-lite.img

# Make sure we have all build-deps
info "Build dependencies"
sudo apt-get -q install \
    wget zip \
    fdisk parted mount \
    binfmt-support qemu-user-static

# Need to restart binfmt after install of qemu for arm
sudo systemctl restart systemd-binfmt.service

# Cached download of the rpi img
info "Downloading diskimage"
cd dl
if [ ! -f 2021-05-07-raspios-buster-armhf-lite.zip ]; then
    wget https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2021-05-28/2021-05-07-raspios-buster-armhf-lite.zip
fi

info "Extracting diskimage"
unzip 2021-05-07-raspios-buster-armhf-lite.zip
cd ..
DISKIMG="dl/2021-05-07-raspios-buster-armhf-lite.img"

# Grow diskimage so we've got enough space for packages etc
info "Growing diskimage"
dd if=/dev/zero bs=1M count=256 >> "$DISKIMG"

# Grow partition 2 to use the extra space
info "Growing partition"
NEWSZ=$( sudo parted -m "$DISKIMG" print | head -2 | tail -1 | cut -d':' -f2 | tr -d MB )
sudo parted "$DISKIMG" resizepart 2 $NEWSZ

# Get some partition info from the diskimage
# Determine sector size and start sector of last (main) partition --> start byte
FDISK=$( sudo fdisk -l "$DISKIMG" -o Start )
SECTOR=$( echo "$FDISK" | grep 'Units' | cut -d' ' -f6 )
START=$( echo "$FDISK" | tail -1 )
STARTBYTE=$(($SECTOR * $START))

# Loop mount the diskimage into the temp directory
info "Loop mounting"
sudo mount -o loop,offset=$STARTBYTE "$DISKIMG" tmp

# We grew the partion previously; need to expand filesystem too
info "Growing filesystem for larger partition"
LOOPDEV=$( sudo losetup --list | grep "$DISKIMG" | cut -d' ' -f1 )
sudo resize2fs $LOOPDEV

# Now a bunch of commands are run via chroot
CHROOT="sudo chroot tmp"

# Let's quickly check that the architecture is correct
info "Checking chroot is working"
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
info "Installing app into /home/pi/carflix"
mkdir -p tmp/home/pi/carflix
cp -r ../app tmp/home/pi/carflix
cp -r ../assets tmp/home/pi/carflix
cp -r ../vendor tmp/home/pi/carflix
cp ../* tmp/home/pi/carflix 2>/dev/null || :
chown 1000:1000 -R tmp/home/pi/carflix
echo "Done"; echo

# Install dependencies
info "Installing dependencies"
$CHROOT apt-get -y update
$CHROOT apt-get -y install \
    golang \
    usbmount \
    exfat-fuse \
    ntfs-3g \
    dnsmasq

# Copy across some config files which makes stuff work
info "Setup config files"
cp conf/interfaces /etc/network/interfaces
cp conf/dnsmasq /etc/dnsmasq.d/carflix

info "Unmounting disk img"
sudo umount -q tmp

info "Done!"
echo
echo "Disk image is located at '$DISKIMG' and can now be copied onto an SD card"
echo
