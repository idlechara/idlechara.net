---
title: Turning an AC1750 router into a homemade Time Capsule
date: Mon Jan 28 2019
tag: dev
slug: timecapsule
excerpt: "You have a Mac but don't have enough money to afford a Time Capsule? Use a router, install OpenWRT, profit."
---
[//]: # (Mon Jan 28 19:31:31 -03 2019)
# Turning an AC1750 router into a homemade timecapsule

You have a Mac but don't have enough money to afford a time capsule? Maybe you have but can't expand it's storage? Here is the solution: Use a router, install OpenWRT and follow the official guides to!

Specials thanks to [@alejandrosazo](https://twitter.com/alejandrosazo) for giving me this router in the past ICPC contest.

## What is a TimeCapsule?

[Wikipedia has a better explanation of what it is](https://en.wikipedia.org/wiki/AirPort_Time_Capsule), but an AirPort Time Capsule is simple terms is a router with a NAS attached. The router is not a marvelous one, nor the NAS attached, but, it allows you to make incremental backups using TimeMachine wirelessly.

The problem is, that those devices are awfully expensive, also, there is nearly no option of expanding it's storage (yeah, Apple devices).

## Solution: The router
We will use an [OpenWRT](https://openwrt.org) compatible router and then we will perform the following tasks:

* Install linux on it (OpenWRT/DDWRT)
* Configuration
* Profit

## Step 1: Installing OpenWRT
OpenWRT is a lightweight linux distribution intented to be run on routers, switches, etc. This is our key element, since we'll be using linux to expose later our hard disk. For that, we first need to identify the router.

![Box](./timecapsule/1.jpeg)
![Ports](./timecapsule/2.jpeg)
![Back](./timecapsule/3.jpeg)
![Front](./timecapsule/4.jpeg)

Here we can identify that this is an TP-Link AC1750 ver. 4.0. Then by checking [OpenWRT sheets about the router](https://openwrt.org/toh/tp-link/archer-c7-1750#tab__firmware_installation) we find that it's suitable to flash with it (another option could be DDWRT), so, we download the firmware and flash it into the device.

![OpenWRT page](./timecapsule/openwrt_firmware.jpg)

For our case, we'll be using the classic DHCP configuration for a wired network.

![Network configuration](./timecapsule/network_config.jpg)
![Network configuration](./timecapsule/upgrade_1.jpg)
![Network configuration](./timecapsule/upgrade_2.jpg)

## Step 2: Configuration

After a successful installation, you should be able to connect it vía `192.168.1.1` and you'll be greeted by LuCi interface. Remember to setup SSH and your root password in case of something.

![Network configuration](./timecapsule/LuCi1.jpg)
![Network configuration](./timecapsule/LuCi2.jpg)
![Network configuration](./timecapsule/LuCi3.jpg)
![Network configuration](./timecapsule/LuCi4.jpg)

Now in order to download the needed drivers, you need to connect to your local network as client, because it's a pain in the ass to not have internet on this machine.


![Attaching to our current WiFi network](./timecapsule/wifi1.jpg)
![Attaching to our current WiFi network](./timecapsule/wifi2.jpg)
![Attaching to our current WiFi network](./timecapsule/wifi3.jpg)
![Attaching to our current WiFi network](./timecapsule/wifi4.jpg)
![Attaching to our current WiFi network](./timecapsule/wifi5.jpg)

Yay, we now can download packages and such

### Preparing users and filesystems

WARNING: Make sure that your HDD works with at most 1A. I tried several HDDs and every disk which operates with more than 1A (1.1A by example) failed to be recognized by the router.

```bash
#create users to manage our time machine
opkg update
opkg install kmod-usb-storage usbutils block-mount kmod-usb-storage-uas kmod-usb-ledtrig-usbport kmod-usb2 gdisk libblkid avahi-utils netatalk nano shadow-groupadd shadow-groupmod shadow-useradd shadow-usermod e2fsprogs kmod-fs-ext4
lsusb -t # check that your device is properly connected
df
block info
```

At this point, you should get this. If not, please refer to the [OpenWRT guide to external storage](https://openwrt.org/docs/guide-user/storage/usb-drives)

![lsusb -t output](./timecapsule/lsusb.jpg)

Then assuming that you have your device mapped to sda1, you'll need to run the following commands to create your partition (just go with the defaults).

```bash
gdisk /dev/sda
o
n
w
y
```

Here is a sample output of the commands:

```
root@OpenWrt:~# gdisk /dev/sda
GPT fdisk (gdisk) version 1.0.3

Partition table scan:
  MBR: MBR only
  BSD: not present
  APM: not present
  GPT: not present


***************************************************************
Found invalid GPT and valid MBR; converting MBR to GPT format
in memory. THIS OPERATION IS POTENTIALLY DESTRUCTIVE! Exit by
typing 'q' if you don't want to convert your MBR partitions
to GPT format!
***************************************************************

Warning! Main partition table overlaps the first partition by 32 blocks!
You will need to delete this partition or resize it in another utility.

Warning! Secondary partition table overlaps the last partition by
33 blocks!
You will need to delete this partition or resize it in another utility.

Command (? for help): o
This option deletes all partitions and creates a new protective MBR.
Proceed? (Y/N): y

Command (? for help): n
Partition number (1-128, default 1):
First sector (34-976773134, default = 2048) or {+-}size{KMGTP}:
Last sector (2048-976773134, default = 976773134) or {+-}size{KMGTP}:
Current type is 'Linux filesystem'
Hex code or GUID (L to show codes, Enter = 8300):
Changed type of partition to 'Linux filesystem'

Command (? for help): w

Final checks complete. About to write GPT data. THIS WILL OVERWRITE EXISTING
PARTITIONS!!

Do you want to proceed? (Y/N): y
OK; writing new GUID partition table (GPT) to /dev/sda.
The operation has completed successfully.
```

After that you'll need to create a new filesystem. The guide says that you should use ext4 for USB HDDs and f2fs for SSDs. Since I only have an external USB HDD, I'll be using ext4.

```bash
mkfs.ext4 /dev/sda1
```

![mkfs output](./timecapsule/mkfs.jpg)

Finally, set automounting partitions in case of your router reboots

```bash
block detect > /etc/config/fstab
uci set fstab.@mount[0].enabled='1'
uci commit
uci set fstab.@global[0].check_fs='1'
uci commit

#reboot
#here it will show your new partition
uci show fstab
```


A good way to save energy consumption and to lessen noise on the room is to stop spinning disks while it's not at use. You can achieve this through LuCi console by installing `luci-app-hd-idle`.

![hdd idle LuCi](./timecapsule/idle_hdd.jpg)


### Configuring AFP

Now we need to configure AFP , in order to serve our disk, so do a `nano /etc/afp.conf` and check the following:

Original content:

```
;
; Netatalk 3.x configuration file
;

[Global]
; Global server settings

; [Homes]
; basedir regex = /xxxx

; [My AFP Volume]
; path = /path/to/volume

; [My Time Machine Volume]
; path = /path/to/backup
; time machine = yes
```

New Content:

```
;
; Netatalk 3.x configuration file
;

[Backups]
     path = /mnt/sda1/Backups
     time machine = yes
     vol size limit = 500000
     valid users = @users
```

Remember to change path to your backup path on the HDD and to set vol size limit to the value that your disk actually exposes.

Avahi should work right out of the box, so no changes needed there. The problem is, current version of Netatalk doesn't come shipped with advertising capabilities, so, we need to write them up ourselves (`nano /etc/avahi/services/afp.servicep`):

```xml
<?xml version="1.0" standalone='no'?><!--*-nxml-*-->
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
 <name replace-wildcards="yes">%h</name>
  <service>
   <type>_afpovertcp._tcp</type>
   <port>548</port>
  </service>
  <service>
   <type>_device-info._tcp</type>
   <port>0</port>
   <txt-record>model=TimeCapsule</txt-record>
  </service>
  <service>
   <type>_adisk._tcp</type>
   <port>9</port>
   <txt-record>sys=waMa=0,adVF=0x100,adVU=6b5fc9dc-2578-40f3-8d14-5f8169939320</txt-record>
   <txt-record>dk0=adVN=Backups,adVF=0x81</txt-record>
  </service>
</service-group>
```

You'll need to change the txt-record uuid (adVU) with a random one.

Now, we change permisions for apf, create a new user to log in the time machine and setup folders.

```bash
chmod 644 /etc/afp.conf
chmod 644 /etc/extmap.conf


useradd --create-home --groups users --user-group kuky_nekoi
passwd kuky_nekoi

cd /mnt/sda1/
mkdir Backups
chmod 775 Backups/
chgrp users Backups/

echo '/etc/afp.conf ' >> /etc/sysupgrade.conf
echo '/etc/avahi/ ' >> /etc/sysupgrade.conf
echo '/etc/extmap.conf ' >> /etc/sysupgrade.conf
echo '/home/ ' >> /etc/sysupgrade.conf
echo '/var/netatalk/ ' >> /etc/sysupgrade.conf
```

And you're done!

Now you have your own time machine using an OpenWRT router.

![profit](./timecapsule/done.jpg)

Byee~!