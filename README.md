# Setup

:warning: This currently results in various problems after installation. It might be possible that this will be resolved after the [alpine 3.23 release](https://wiki.alpinelinux.org/wiki/Draft_Release_Notes_for_Alpine_3.23.0). Especially the `/usr-merge` might be necessary. See [this](https://gist.github.com/leomeinel/e9af276afba84e6b64e635b578314d94) for details. The current workaround is to not use a separate `/usr` partition.

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
/root/alpine-install/prepare.sh 2>&1 | tee ./prepare.sh.log
/root/alpine-install/setup.sh 2>&1 | tee ./setup.sh.log
```
