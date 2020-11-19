<!-- TOC -->
this is a test
<!-- TOC -->



# Hardware Setup

## NVMe

### Overprovisioning

Set 336 GB (14-28%, avg 21%) as reserved for the controller, per device - for
the first (and only) NVMe namespace per device. So the namespace is **1264 GB**
in absolute size.

```
Given 1.6 TB (1600 GB) as 100%
= 336 GB as 21%
```

```shell
$ nvme delete-ns /dev/nvme0n1
$ nvme create-ns /dev/nvme0
```

* https://wiki.archlinux.org/index.php/Solid_state_drive/NVMe
* https://www.kingston.com/germany/de/ssd/overprovisioning

### Sector Size

* https://wiki.archlinux.org/index.php/Solid_state_drive#Maximizing_performance

### Benchmark

```shell
hdparm -Tt --direct /dev/nvme0n1
```

### Firmware Updates

TODO: Document this.
* https://aur.archlinux.org/packages/samsung-ssd-dc-toolkit/

## RAID

### ESP / EFI system partion (RAID1)

TODO: Document this.

### Root partition (RAID0)

TODO: Document this.

## Filesystem

### ESP / EFI system partion (/boot)

TODO: Document this.
* https://wiki.archlinux.org/index.php/EFI_system_partition

### Root partition (/)

TODO: Document this.
* https://wiki.archlinux.org/index.php/F2FS

# Software Installation

## ArchLinux

TODO: Document this.

## Bootloader

TODO: Document this.
* https://wiki.archlinux.org/index.php/Systemd-boot
