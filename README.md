# Setup

This is meant for a system that uses an nvme ssd that requires `dtparam=pciex1_gen=3` to even be detected.

## Configure eeprom

Add the following via `rpi-eeprom-config --edit` in the default raspberrypi os image:

```conf
[all]
BOOT_UART=0
WAKE_ON_GPIO=0
POWER_OFF_ON_HALT=1
BOOT_ORDER=0xf641
PCIE_PROBE=1
```

## Pre-installation

Execute the following with the alpine image from rpi-imager mounted to `/mnt`:

```sh
doas sh -c '{
    echo "# alpine-install"
    echo "## nvme"
    echo "dtparam=pciex1"
    echo "dtparam=pciex1_gen=3"
} >/mnt/usercfg.txt'
doas umount /mnt
```

## Installation

Execute the following scripts:

```sh
/root/alpine-install/prepare.sh
/root/alpine-install/setup.sh
```
