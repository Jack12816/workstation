<!-- TOC-START -->
- [Hardware Setup](#hardware-setup)
  - [BIOS / EFI](#bios--efi)
    - [CPU](#cpu)
      - [LLC Prefetch](#llc-prefetch)
  - [Starting ArchLinux Installation](#starting-archlinux-installation)
    - [Verify the EFI boot mode](#verify-the-efi-boot-mode)
    - [Setup Network](#setup-network)
    - [Update the system clock](#update-the-system-clock)
  - [NVMe](#nvme)
    - [Sector Size](#sector-size)
    - [Overprovisioning](#overprovisioning)
    - [Firmware Updates](#firmware-updates)
    - [Benchmark](#benchmark)
  - [RAID](#raid)
    - [Partition the drives](#partition-the-drives)
    - [Clean any old RAID configuration](#clean-any-old-raid-configuration)
    - [Root partition (RAID0)](#root-partition-raid0)
  - [Filesystem](#filesystem)
    - [ESP / EFI system partion (/boot)](#esp--efi-system-partion-boot)
    - [Root partition (/)](#root-partition-)
- [Software Installation](#software-installation)
  - [ArchLinux](#archlinux)
  - [Bootloader](#bootloader)
  - [First Reboot](#first-reboot)
- [Configuration](#configuration)
  - [Tune Kernel Parameters](#tune-kernel-parameters)
    - [Disable CPU exploit mitigations](#disable-cpu-exploit-mitigations)
    - [Disable Watchdogs](#disable-watchdogs)
  - [Periodic TRIM](#periodic-trim)
  - [Package Compilation in tmpfs](#package-compilation-in-tmpfs)
  - [Docker Repository in tmpfs](#docker-repository-in-tmpfs)
  - [Tune System Controls](#tune-system-controls)
  - [General Performance Tuning](#general-performance-tuning)
  - [GPU Configuration](#gpu-configuration)
  - [UPS Configuration](#ups-configuration)
- [Benchmarking](#benchmarking)
<!-- TOC-END -->

# Hardware Setup

## BIOS / EFI

### CPU

#### LLC Prefetch

**Enable** LLC Prefetching (disabled by default).

This option configures the processor Last Level Cache (LLC) prefetch feature as
a result of the non-inclusive cache architecture. The LLC prefetcher exists on
top of other prefetchers that that can prefetch data in the core data cache
unit (DCU) and mid-level cache(MLC). In some cases, setting this option to
disabled can improve performance. Typically, setting this option to enable
provides better performance.

## Starting ArchLinux Installation

### Verify the EFI boot mode

Just check for files at `$ ls /sys/firmware/efi/efivars`. When there are files
present, everything is fine.

**References:**
* https://wiki.archlinux.org/index.php/Installation_guide#Verify_the_boot_mode

### Setup Network

Make sure the interfaces are up and running - by default the 10GbE LAN port
does not get a DHCP-set IP config. Just plug in the 1GbE LAN port. Afterwards
enable the interfaces like this:

```shell
$ ip link set eno1 up
$ ip link set eth1 up
$ systemctl restart dhcpcd.service
$ systemctl status dhcpcd.service
$ ping google.com
```

**References:**
* https://wiki.archlinux.org/index.php/Network_configuration

### Update the system clock

Sync the SW/HW clock via NTP to the correct time. This ensures correct
filesystem times, etc.

`$ timedatectl set-ntp true`

**References:**
* https://wiki.archlinux.org/index.php/Installation_guide#Update_the_system_clock

## NVMe

### Sector Size

The Samsung PM1725b is capable of 4 kB sectors. So we the best LBA (Logical
block addressing) format is **#3** (lbaf: 2). See the description:

```
lbaf 2 : ms:0  lbads:12  rp:0
     |      |        |      |
     |      |        |      `-- Relative Performance (with 0 being the best)
     |      |        |
     |      |        `-- 2 ^ 12 = 4 kB sectors
     |      |
     |      `-- extra metadata bytes per sector, and this is not well
     |          supported under Linux so best to select a format with
     |          a value of 0 here.
     |
     `-- nlbaf is the number of LBA formats minus 1.
         Here lbaf 2 means LBA format #3.
```

We set the sector size correctly while re-creating the namespace. See [NVMe
Overprovisioning](#overprovisioning).

**References:**
* https://wiki.archlinux.org/index.php/Solid_state_drive#Native_sector_size

### Overprovisioning

After an SSD is assembled, the SSD manufacturer can reserve an additional
percentage of the total drive capacity for Over-Provisioning (OP) during
firmware programming. Over-provisioning improves performance and often
increases the endurance of the SSD, helping the drive last longer due to the
SSD Controller having more Flash NAND storage available to alleviate NAND Flash
wear over its useful life.

Set 336 GB (14-28%, avg 21%) as reserved for the controller, per device - for
the first (and only) NVMe namespace per device. So the namespace is **1264 GB**
in absolute size.

```
Given 1600321314 kB (1.6 TB, 1600321314816 byte) as 100%
= 336067475 kB (336 GB) as 21% (reserve)

total - reserved = new namespace size/cap
1600321314 kB (1.6 TB)  - 336067475 kB (336 GB)
= 1264253839 kB (1.264 GB) new namespace size/cap

new namespace size/cap / sector size = final namespace size
1264253839 kB (1.264 GB) / 4 kB
= 316063459 blocks
```

```shell
# Drive #1
$ nvme delete-ns /dev/nvme0n1
$ nvme create-ns /dev/nvme0 --nsze 316063459 --ncap 316063459 --flbas 2 --dps 0 --nmic 0x1
$ nvme attach-ns /dev/nvme0 --namespace-id=1 --controllers=0x21
$ nvme reset /dev/nvme0

# Drive #2
$ nvme delete-ns /dev/nvme1n1
$ nvme create-ns /dev/nvme1 --nsze 316063459 --ncap 316063459 --flbas 2 --dps 0 --nmic 0x1
$ nvme attach-ns /dev/nvme1 --namespace-id=1 --controllers=0x21
$ nvme reset /dev/nvme1

# Check the setup
$ nvme list

# Node             SN                   Model                                    Namespace Usage                      Format           FW Rev
# ---------------- -------------------- ---------------------------------------- --------- -------------------------- ---------------- --------
# /dev/nvme0n1     S4CBNA0N700159       SAMSUNG MZPLL1T6HAJQ-00005               1           1.29  TB /   1.29  TB      4 KiB +  0 B   GPJA2B3Q
# /dev/nvme1n1     S4CBNA0N700150       SAMSUNG MZPLL1T6HAJQ-00005               1           1.29  TB /   1.29  TB      4 KiB +  0 B   GPJA2B3Q
```

Check the lbaf in use with: `$ nvme id-ns /dev/nvme0n1`.

**References:**
* https://wiki.archlinux.org/index.php/Solid_state_drive/NVMe
* https://www.kingston.com/germany/de/ssd/overprovisioning
* https://wiki.archlinux.org/index.php/Solid_state_drive#Maximizing_performance
* https://nvmexpress.org/resources/nvm-express-technology-features/nvme-namespaces/
* https://www.linuxjournal.com/content/data-flash-part-ii-using-nvme-drives-and-creating-nvme-over-fabrics-network

### Firmware Updates

TODO: Research, perform, document this.

```shell
$ nvme help fw-download
```

**References:**
* https://aur.archlinux.org/packages/samsung-ssd-dc-toolkit/

### Benchmark

```shell
$ hdparm -Tt --direct /dev/nvme0n1
# Timing O_DIRECT cached reads:   6324 MB in  2.00 seconds = 3163.52 MB/sec
# Timing O_DIRECT disk reads: 9538 MB in  3.00 seconds = 3178.72 MB/sec

$ hdparm -Tt --direct /dev/nvme1n1
# Timing O_DIRECT cached reads:   6428 MB in  2.00 seconds = 3214.57 MB/sec
# Timing O_DIRECT disk reads: 9682 MB in  3.00 seconds = 3227.16 MB/sec
```

**References:**
* https://www.archlinux.org/packages/community/any/iotop/

## RAID

### Partition the drives

We use a simple partitioning scheme with two partions. The first is the EFI
system partition (containing also /boot), and the second is the root partition,
including also all user data.

```shell
# Drive #1
$ parted /dev/nvme0n1 mklabel gpt
$ parted /dev/nvme0n1 mkpart '"EFI system partition"' fat32 1MiB 1GiB
$ parted /dev/nvme0n1 set 1 esp on
$ parted /dev/nvme0n1 mkpart '"root partition"' xfs 1GiB 100%
$ parted /dev/nvme0n1 set 2 raid on
$ parted /dev/nvme0n1 align-check optimal 1
$ parted /dev/nvme0n1 align-check optimal 2
$ gdisk -l /dev/nvme0n1

# Found valid GPT with protective MBR; using GPT.
# Disk /dev/nvme0n1: 316063459 sectors, 1.2 TiB
# Model: SAMSUNG MZPLL1T6HAJQ-00005
# Sector size (logical/physical): 4096/4096 bytes
# Disk identifier (GUID): F4B27D8E-3C49-4854-BBF8-B5B03461C948
# Partition table holds up to 128 entries
# Main partition table begins at sector 2 and ends at sector 5
# First usable sector is 6, last usable sector is 316063453
# Partitions will be aligned on 256-sector boundaries
# Total free space is 472 sectors (1.8 MiB)
#
# Number  Start (sector)    End (sector)  Size       Code  Name
#    1             256          262143   1023.0 MiB  EF00  EFI system partition
#    2          262144       316063231   1.2 TiB     FD00  root partition

# Drive #2
$ parted /dev/nvme1n1 mklabel gpt
$ parted /dev/nvme1n1 mkpart '"EFI system partition (sparse)"' fat32 1MiB 1GiB
$ parted /dev/nvme1n1 mkpart '"root partition"' xfs 1GiB 100%
$ parted /dev/nvme1n1 set 2 raid on
$ parted /dev/nvme1n1 align-check optimal 1
$ parted /dev/nvme1n1 align-check optimal 2
$ gdisk -l /dev/nvme1n1

# Found valid GPT with protective MBR; using GPT.
# Disk /dev/nvme1n1: 316063459 sectors, 1.2 TiB
# Model: SAMSUNG MZPLL1T6HAJQ-00005
# Sector size (logical/physical): 4096/4096 bytes
# Disk identifier (GUID): 7F4F6109-A97D-4CA6-8BF3-CA68594112D6
# Partition table holds up to 128 entries
# Main partition table begins at sector 2 and ends at sector 5
# First usable sector is 6, last usable sector is 316063453
# Partitions will be aligned on 256-sector boundaries
# Total free space is 472 sectors (1.8 MiB)
#
# Number  Start (sector)    End (sector)  Size       Code  Name
#    1             256          262143   1023.0 MiB  0700  EFI system partitio...
#    2          262144       316063231   1.2 TiB     FD00  root partition
```

**References:**
* https://wiki.archlinux.org/index.php/Installation_guide#Partition_the_disks
* https://wiki.archlinux.org/index.php/Partitioning

### Clean any old RAID configuration

In case of a re-installation, clear the old RAID configuration like this:

```shell
$ mdadm --stop /dev/md/root
$ mdadm --misc --zero-superblock /dev/nvme0n1p2
$ mdadm --misc --zero-superblock /dev/nvme1n1p2
```

**References:**
* https://wiki.archlinux.org/index.php/RAID#Prepare_the_devices

### Root partition (RAID0)

```shell
$ mdadm --create --verbose --level=0 --metadata=1.2 --raid-devices=2 \
    --homehost=any \
    /dev/md/root /dev/nvme0n1p2 /dev/nvme1n1p2
$ cat /proc/mdstat
$ mdadm --detail /dev/md/root

#            Version : 1.2
#      Creation Time : Sun Nov 22 13:56:39 2020
#         Raid Level : raid0
#         Array Size : 2526144512 (2409.12 GiB 2586.77 GB)
#       Raid Devices : 2
#      Total Devices : 2
#        Persistence : Superblock is persistent
#
#        Update Time : Sun Nov 22 13:56:39 2020
#              State : clean
#     Active Devices : 2
#    Working Devices : 2
#     Failed Devices : 0
#      Spare Devices : 0
#
#         Chunk Size : 512K
#
# Consistency Policy : none
#
#               Name : any:root
#               UUID : eab2dc89:254f1e72:ff067e91:434e37a0
#             Events : 0
#
#     Number   Major   Minor   RaidDevice State
#        0     259        5        0      active sync   /dev/nvme0n1p2
#        1     259        7        1      active sync   /dev/nvme1n1p2
```

**References:**
* https://wiki.archlinux.org/index.php/RAID

## Filesystem

### ESP / EFI system partion (/boot)

We setup a ESP for direct booting. This partition will also hold all /boot
files, including the kernel and the initramfs. Unfortunately, it is problematic
for an ESP to reside on a RAID1 volume, so we create a sparse (empty) partition
on the other NVMe drive. When one NVMe drive fails, we are in "bigger trouble"
with the system RAID0 volume. UPS and hourly backups will help here.

```shell
$ mkfs.fat -F32 -s2 /dev/nvme0n1p1
$ mkfs.fat -F32 -s2 /dev/nvme1n1p1 # will be empty (sparse)
```

**References:**
* https://wiki.archlinux.org/index.php/EFI_system_partition
* https://wiki.archlinux.org/index.php/EFI_system_partition#Format_the_partition

### Root partition (/)

We spare the separation of system and data partitions, in favor of performance
and less overhead of on-disk-format space waste. With XFS we have the best in
class enterprise filesystem (EXT4/XFS are RedHat Enterprise supported) which
works great (even better than F2FS) on high-end NVMe drives for many (massive
amount) small files.

Correct stripe width and stride:

* RAID0 array is composed of 2 physical disks
* Chunk size is 512 KiB (default by mdadm)
* Block size is 4 KiB (set this before on the NVMe namespaces)

```
stride = chunk size / block size. The math is 512/4 so the stride = 128.
stripe width = # of physical data disks * stride.
The math is 2*128 so the stripe width = 256.

=> stride=128 *
=> stripe-width=256 **
=> block-size=4kb ***
```

```shell
$ mkfs.xfs /dev/md/root

# meta-data=/dev/md/root           isize=512    agcount=32, agsize=19735424 blks
#          =                       sectsz=4096  attr=2, projid32bit=1
#          =                       crc=1        finobt=1, sparse=1, rmapbt=0
#          =                       reflink=1
# data     =                       ***bsize=4096   blocks=631533568, imaxpct=5
#          =                       *sunit=128   **swidth=256 blks
# naming   =version 2              bsize=4096   ascii-ci=0, ftype=1
# log      =internal log           bsize=4096   blocks=308366, version=2
#          =                       sectsz=4096  sunit=1 blks, lazy-count=1
# realtime =none                   extsz=4096   blocks=0, rtextents=0
# Discarding blocks...Done.

$ mount /dev/md/root /mnt
$ mkdir -p /mnt/boot /mnt/data
$ mount /dev/nvme0n1p1 /mnt/boot
```

**References:**
* https://wiki.archlinux.org/index.php/XFS
* https://wiki.archlinux.org/index.php/F2FS
* https://github.com/torvalds/linux/blob/master/Documentation/filesystems/f2fs.rst#mount-options

# Software Installation

## ArchLinux

Now as the hardware setup is done, we can install the basic ArchLinux system to
RAID0 array/volume.

```shell
# Select the pacman mirrors
$ cat <<'EOF' >/etc/pacman.d/mirrorlist
Server = http://ftp.fau.de/archlinux/$repo/os/$arch
Server = https://mirror.mikrogravitation.org/archlinux/$repo/os/$arch
Server = https://mirror.wtnet.de/arch/$repo/os/$arch
Server = https://arch.eckner.net/archlinux/$repo/os/$arch
Server = http://ftp.gwdg.de/pub/linux/archlinux/$repo/os/$arch
Server = https://ftp.fau.de/archlinux/$repo/os/$arch
EOF

# Install essential packages
$ pacstrap /mnt base linux linux-firmware \
    vim htop sudo git \
    dosfstools xfsprogs mdadm \
    iputils iproute2 net-tools inetutils openssh \
    intel-ucode iucode-tool

# Generate the new system fstab
$ genfstab -U /mnt >> /mnt/etc/fstab
$ echo 'tmpfs /dev/shm tmpfs defaults,size=64g 0 0' >> /mnt/etc/fstab
$ vim /mnt/etc/fstab

# Write the current raid array config
$ mdadm --detail --scan >> /mnt/etc/mdadm.conf
$ cat /mnt/etc/mdadm.conf
```

The base installation is completed. No chroot into the new system
and configure the basics:

```shell
# Enter the new system
$ arch-chroot /mnt

# Enable mdadm on boot
$ vim /etc/mkinitcpio.conf
# HOOKS=(.. block mdadm_udev filesystems ..)
$ mkinitcpio -p linux

# Configure the hostname
$ hostnamectl set-hostname workstation.lan
$ echo 'workstation.lan' > /etc/hostname
$ cat /etc/hostname
$ echo '127.0.0.1 localhost' >> /etc/hosts
$ echo '::1 localhost' >> /etc/hosts
$ echo '127.0.1.1 workstation.localdomain workstation.lan workstation' >> /etc/hosts
$ cat /etc/hosts

# Set correct time(zone) settings
$ ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
$ hwclock --systohc

# Configure UTF-8 support for the en_US locale
$ echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
$ echo 'LANG=en_US.UTF-8' > /etc/locale.conf
$ locale-gen

# Set the root password
$ passwd

# Enable the SSH daemon on the new system
$ systemctl enable sshd
$ echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
```

**References:**
* https://wiki.archlinux.org/index.php/Installation_guide
* https://wiki.archlinux.org/index.php/Microcode
* https://wiki.archlinux.org/index.php/OpenSSH

## Bootloader

We make use of systemd-boot (former Gummiboot) for booting the system as a
direct UEFI client application. This bootloader is very simple, lightweight,
has no interface which let the user wait per boot and comes bundled with
systemd.

```shell
# Install the bootloader
$ bootctl install

# Configure the default loader
$ make configure-bootloader
```

**References:**
* https://wiki.archlinux.org/index.php/Systemd-boot
* https://wiki.archlinux.org/index.php/Unified_Extensible_Firmware_Interface#For_GPT_partitioned_disks
* https://outflux.net/blog/archives/2018/04/19/uefi-booting-and-raid1/
* https://github.com/systemd/systemd/issues/17530#issuecomment-724096121

## First Reboot

The installation of the basic ArchLinux system is done. Just exit the chroot
and reboot the machine with `$ reboot`.

# Configuration

## Tune Kernel Parameters

### Disable CPU exploit mitigations

Add `mitigations=off` to the kernel options. This will disable all CPU exploit
mitigations, to maximize performance.

**References:**
* https://wiki.archlinux.org/index.php/improving_performance#Turn_off_CPU_exploit_mitigations

### Disable Watchdogs

Add `nowatchdog` and `nmi_watchdog=0` to the kernel options. Additionaly
blacklist the watchdog kernel modules like this:

```shell
$ make configure-watchdogs
```

**References:**
* https://wiki.archlinux.org/index.php/improving_performance#Watchdogs

## Periodic TRIM

The service executes fstrim(8) on all mounted filesystems on devices that
support the discard operation.

```shell
$ make configure-periodic-trim
```

**References:**
* https://wiki.archlinux.org/index.php/Solid_state_drive#Periodic_TRIM

## Package Compilation in tmpfs

The default parallel jobs where set to **24**, the build directory was
relocated to shared memory, the compression tool settings now feature parallel
optimizations and the default package extension disables compression
completely. This should speed up AUR builds a lot.

```
$ make configure-package-compilation
```

**References:**
* https://wiki.archlinux.org/index.php/Makepkg#Improving_compile_times
* https://wiki.archlinux.org/index.php/Makepkg#Utilizing_multiple_cores_on_compression




---



## Docker Repository in tmpfs

TODO: Research, perform, document this.

**References:**
* https://wiki.archlinux.org/index.php/Anything-sync-daemon
* https://github.com/graysky2/anything-sync-daemon





## Tune System Controls

TODO: Research, perform, document this.

**References:**
* https://wiki.archlinux.org/index.php/Sysctl#Virtual_memory
* https://tuned-project.org/
* https://github.com/redhat-performance/tuned/tree/master/profiles
* https://aur.archlinux.org/packages/tuned/
* https://documentation.suse.com/sbp/all/html/SBP-performance-tuning/index.html#sec-bios-setup
* https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html-single/performance_tuning_guide/index








## General Performance Tuning

TODO: Research, perform, document this.

**References:**
* https://wiki.archlinux.org/index.php/improving_performance

## GPU Configuration

TODO: Research, perform, document this.

Packages: xf86-video-amdgpu vulkan-radeon lib32-vulkan-radeon libva-mesa-driver mesa-vdpau libvdpau-va-gl libva-vdpau-driver gstreamer-vaapi gst-plugins-bad
AUR Packages: radeontop

**References:**
* https://wiki.archlinux.org/index.php/AMDGPU
* https://wiki.archlinux.org/index.php/Xorg#AMD
* https://wiki.archlinux.org/index.php/Kernel_mode_setting#Early_KMS_start
* https://github.com/clbr/radeontop
* https://wiki.archlinux.org/index.php/Hardware_video_acceleration
* chrome://gpu/

## UPS Configuration

TODO: Research, perform, document this.

**References:**
* https://wiki.archlinux.org/index.php/APC_UPS





# Benchmarking

TODO: Research, perform, document this.

**References:**
* https://openbenchmarking.org/suite/pts/disk
* https://openbenchmarking.org/suite/pts/workstation
* https://wiki.archlinux.org/index.php/benchmarking#Phoronix_Test_Suite
* https://aur.archlinux.org/packages/phoronix-test-suite/
* https://wiki.archlinux.org/index.php/benchmarking#S
* http://www.phoronix-test-suite.com/?k=features
