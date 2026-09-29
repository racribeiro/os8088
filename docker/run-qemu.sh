#!/bin/sh
set -eu

make

# A persistent 20 MiB primary IDE disk.  It starts blank deliberately: the
# OS8088 hard-disk driver and formatter are what initialise its partition and
# filesystem, not the container launcher.
hdd=build/qemu-hdd.img
if [ ! -e "$hdd" ]; then
    truncate -s 20M "$hdd"
fi

# Match the QEMU development hardware profile: an SB16 (its audio is not
# transported by noVNC, so use the silent backend) and an ISA NE2000 at the
# address and IRQ expected by ETHER.DRV.  User-mode NAT gives the guest
# outbound networking without requiring privileged host networking setup.
exec qemu-system-i386 \
    -drive file=build/os8088.img,format=raw,if=floppy \
    -boot a \
    -chardev msmouse,id=m0 \
    -serial chardev:m0 \
    -drive file=build/apps.img,format=raw,if=floppy,index=1 \
    -drive file="$hdd",format=raw,if=ide,index=0 \
    -audiodev none,id=snd \
    -device sb16,audiodev=snd \
    -netdev user,id=n0 \
    -device ne2k_isa,netdev=n0,iobase=0x300,irq=3 \
    -display none \
    -vnc 0.0.0.0:0
