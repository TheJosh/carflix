#!/bin/bash
# Needs root for deps and chroot and stuff
# Tested on Debian, but should work on other deb systems easily,
# and can probably be ported to other distros pretty easily


# Country code for WiFi use
COUNTRY="AU"

# Should we configure access-point mode?
# If set to Y then the rpi will act as an access point hosting
# it's own private (non-internet) network. Very useful in remote
# situations such as cars, caravans, boats, etc.
APMODE="Y"

# Unmount the loop device once finished. Set this to "N" if you'd
# like to make your own modifications afterwards. Don't forget to
# unmount the 'tmp' directory when you're finished!
UNMOUNT="Y"


set -e
cd `dirname $0`

info () {
    echo -e "\033[1;33m${1}\033[0m"
}

# Basic setup + cleanup in case of failed previous run
mkdir -p dl tmp out
sudo umount -q tmp || :
rm -f out/2021-05-07-raspios-buster-armhf-lite.img

# Cross compile app, ready for install later
# Done first, so that we can catch build failures quickly
info "Cross-compiling app for ARM"
pushd ..
env GOOS=linux GOARCH=arm go build -o carflix-diskimg .
popd

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
mv dl/2021-05-07-raspios-buster-armhf-lite.img out/carflix-buster-armhf.img
DISKIMG="out/carflix-buster-armhf.img"

# Grow diskimage so we've got enough space for packages etc
info "Growing diskimage"
dd if=/dev/zero bs=1M count=256 >> "$DISKIMG"
sync "$DISKIMG"

# Grow partition 2 to use the extra space
info "Growing partition"
sudo parted "$DISKIMG" resizepart 2 100%
sync "$DISKIMG"

# Get some partition info from the diskimage
# Determine sector size and start sector of last (main) partition --> start byte
info "Finding partition start byte"
FDISK=$( sudo fdisk -l "$DISKIMG" -o Start,End,Sectors,Device,Size,Type )
echo "$FDISK"
SECTOR=$( echo "$FDISK" | grep 'Units' | cut -d' ' -f6 )
START=$( echo "$FDISK" | tail -1 | cut -d' ' -f1 )
STARTBYTE=$(($SECTOR * $START))
echo "Start byte: $STARTBYTE"

# We grew the partion previously; need to expand filesystem too
info "Growing filesystem for larger partition"
sudo losetup -P /dev/loop10 "$DISKIMG" -o $STARTBYTE
sudo resize2fs /dev/loop10

# Make sure it was okay
info "Checking filesystem"
sudo e2fsck -f /dev/loop10
sudo losetup -d /dev/loop10
echo

# Loop mount the diskimage into the temp directory
info "Loop mounting"
sudo mount -o loop,offset=$STARTBYTE "$DISKIMG" tmp
sudo df -h tmp/usr
echo

# Now a bunch of commands are run via chroot
PWD=$( pwd )
CHROOT="sudo chroot $PWD/tmp"

# Silence a bunch of irritable warnings
LANGUAGE=C
LC_ALL=C
LANG=C

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

info "Couple of useful config tweaks"
# Some changes to fstab to improve power-loss safety -- mount in "sync" mode
sudo gawk -i inplace -F '[[:space:]][[:space:]]+' '$2=="/"{$4="defaults,noatime,ro"} 1' tmp/etc/fstab
sudo echo -c 'cat conf/fstab >> tmp/etc/fstab'
# Fix for usbmount auto-mounting
sudo sed -i "s/PrivateMounts=yes/PrivateMounts=no/" tmp/lib/systemd/system/systemd-udevd.service
# Improved solution (upgrade-safe):
# https://raspberrypi.stackexchange.com/a/107449
echo

# Install dependencies
info "Installing app dependencies"
$CHROOT apt-get -y update
$CHROOT apt-get -y install \
    usbmount \
    exfat-fuse ntfs-3g

info "Removing unwanted services"
$CHROOT systemctl disable x11-common

# Copy source code + build the app
# This is better than "run" because it won't require git or network
info "Installing app"
mkdir -p tmp/home/pi/carflix
cp ../carflix-diskimg tmp/home/pi/carflix/carflix
cp -r ../assets tmp/home/pi/carflix
chown 1000:1000 -R tmp/home/pi/carflix
echo "Done"; echo

# Install the extra parts for this
if [ "$APMODE" = "Y" ]; then
    info "Installing access-point dependencies"
    $CHROOT apt-get -y install hostapd dnsmasq

    # Copy across some config files which makes stuff work
    info "Write config files"
    sudo cp conf/dnsmasq tmp/etc/dnsmasq.d/carflix
    sudo cp conf/hostapd tmp/etc/hostapd/hostapd.conf
    sudo cp conf/rc-local tmp/etc/rc.local

    # This file is appended instead
    sudo bash -c 'cat conf/dhcpcd-static >> tmp/etc/dhcpcd.conf'

    # Set correct country + enable config for systemd unit
    sudo sed -i "s/country_code=AU/country_code=$COUNTRY/" tmp/etc/hostapd/hostapd.conf
    sudo sed -i "s/#DAEMON_CONF=\"\"/DAEMON_CONF=\"\/etc\/hostapd\/hostapd.conf\"/" tmp/etc/default/hostapd

    # Enable the services
    info "Enable networking services"
    $CHROOT systemctl unmask hostapd
    $CHROOT systemctl enable hostapd
    $CHROOT systemctl enable dnsmasq
fi
echo

# Did we fill the disk?
info "Checking free space"
sudo df -h tmp/usr

# Install the extra parts for this
if [ "$UNMOUNT" != "Y" ]; then
    echo
    info "Done!"
    echo "As requested, leaving 'tmp' mounted."
    exit 0
fi

# We're done. Unmount the image
info "Unmounting disk img"
sudo umount -q tmp
sync "$DISKIMG"

# Recheck the filesystem was okay
info "Recheck filesystem"
sudo losetup /dev/loop10 "$DISKIMG" -o $STARTBYTE
sudo e2fsck -f /dev/loop10
sudo losetup -d /dev/loop10
echo

info "Done!"
echo
echo "Disk image is located at '$DISKIMG' and can now be copied onto an SD card"
echo
