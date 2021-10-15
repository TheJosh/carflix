# Carflix

Local streaming server for media files, which doesn't require any internet
access. Can be installed onto a portable computer (e.g. Raspberry Pi) for
portable media streaming via a WiFi hotspot.


## Getting started

Run with `go run .`


## Content locations

Video content is searched in the following locations:

- The "content" directory in this repository
- The "Videos" directory within the homedir
- All mounted external devices

External devices are searched using the `lsblk` utility. If auto-mount is
configured for USB devices, then you should be able to use these seamlessly.

If content is changed, then you must re-scan; this can be done using the
**Reload Videos** menu option in the top-right corner of the web interface.


## Use with a Raspberry Pi

Carflix has been tested with a Raspberry Pi 3A which has WiFi support. You
can also put the PI into "Access Point" mode for fully remote video hosting.

1. Download this repository onto the RPi -- `git clone https://github.com/TheJosh/carflix.git`
2. Install the GO libraries with `sudo apt install golang`
3. Install ffmpeg for thumbnail generation, `sudo apt install ffmpeg`
4. Run with `go run .`
