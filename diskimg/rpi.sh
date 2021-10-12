#!/bin/bash
# Needs root for deps and chroot and stuff
# Tested on Debian, but should work on other deb systems easily,
# and can probably be ported to other distros pretty easily

cd `dirname $0`
mkdir -p dl tmp

# Make sure we have all build-deps
sudo apt install \
    wget \
    zip \
    binfmt-support \
    qemu-user-static

# Need to restart binfmt after install of qemu for arm
sudo systemctl restart systemd-binfmt.service

# Cached download of the rpi img
pushd dl
if [ ! -f 2021-05-07-raspios-buster-armhf-lite.img ]; then
    wget https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2021-05-28/2021-05-07-raspios-buster-armhf-lite.zip
    unzip 2021-05-07-raspios-buster-armhf-lite.zip
fi
popd
