[//]: # (sun mar 24 21:06:07 -03 2019)
# Parabuntu, updated to 18.04 (with download link)

In this post I'll explain how to upgrade your old parabuntu image to the latest ubuntu release.

Things to get into consideration:
* Latest version of ubuntu shipped for parallella is no longer supported. This will cause all current methods to fail misserably.
* This is a "not recommended way" to do things, but there is no other options at this point.

If you're lazy to do all of this by yourself, there is a downloadable link for the image that I use, which has Ubuntu 18.04 and no E-Link support (since I use my Parallella for FPGA development and to be honest, the E16 chip sucks).

## Hands-on tutorial
First of all, this problem arised a long time ago, since support for Vivid LTS ended. Since that time, no mirrors support this version anymore and this prevents us to upgrade to other versions using the standard way:

```bash
# standard way to update
sudo do-release-upgrade # will fail
```

For a more accurrate description of the problem: https://github.com/parallella/parabuntu/issues/13.

In this thread, there is a reply which suggest to upgrade to *Willy*, sadly, *Willy* doesn't have any LTS versions available by now, so we'll stick with *Xenial*.

After you go to [Ubuntu sources generator](https://repogen.simplylinux.ch) you'll get something like this (after doing all the process):

```bash
#------------------------------------------------------------------------------#
#                            OFFICIAL UBUNTU REPOS                             #
#------------------------------------------------------------------------------#


###### Ubuntu Main Repos
deb http://archive.ubuntu.com/ubuntu/ xenial main restricted universe multiverse 
deb-src http://archive.ubuntu.com/ubuntu/ xenial main restricted universe multiverse 

###### Ubuntu Update Repos
deb http://archive.ubuntu.com/ubuntu/ xenial-security main restricted universe multiverse 
deb http://archive.ubuntu.com/ubuntu/ xenial-updates main restricted universe multiverse 
deb http://archive.ubuntu.com/ubuntu/ xenial-proposed main restricted universe multiverse 
deb-src http://archive.ubuntu.com/ubuntu/ xenial-security main restricted universe multiverse 
deb-src http://archive.ubuntu.com/ubuntu/ xenial-updates main restricted universe multiverse 
deb-src http://archive.ubuntu.com/ubuntu/ xenial-proposed main restricted universe multiverse 

###### Ubuntu Partner Repo
deb http://archive.canonical.com/ubuntu xenial partner
deb-src http://archive.canonical.com/ubuntu xenial partner
```

In fact, this is ok since it will point us to the official mirros for this version of the distribution. Problem is, there is no available packages for our architecture (armhf).

In order to overcome this problem use this [ubuntu ports reference page](https://wiki.ubuntu.com/UbuntuDevelopment/PackageArchive#Ports), there they state that THERE IS a repo for armhf, so, we change our previously generated repo file replacing all ocurrences of `http://archive.ubuntu.com/ubuntu/` with ``http://ports.ubuntu.com/ubuntu-ports/. So, our file will look as follows:


```bash
#------------------------------------------------------------------------------#
#                            OFFICIAL UBUNTU REPOS                             #
#------------------------------------------------------------------------------#


###### Ubuntu Main Repos
deb http://ports.ubuntu.com/ubuntu-ports/ xenial main restricted universe multiverse 
deb-src http://ports.ubuntu.com/ubuntu-ports/ xenial main restricted universe multiverse 

###### Ubuntu Update Repos
deb http://ports.ubuntu.com/ubuntu-ports/ xenial-security main restricted universe multiverse 
deb http://ports.ubuntu.com/ubuntu-ports/ xenial-updates main restricted universe multiverse 
deb http://ports.ubuntu.com/ubuntu-ports/ xenial-proposed main restricted universe multiverse 
deb-src http://ports.ubuntu.com/ubuntu-ports/ xenial-security main restricted universe multiverse 
deb-src http://ports.ubuntu.com/ubuntu-ports/ xenial-updates main restricted universe multiverse 
deb-src http://ports.ubuntu.com/ubuntu-ports/ xenial-proposed main restricted universe multiverse 

###### Ubuntu Partner Repo
deb http://archive.canonical.com/ubuntu xenial partner
deb-src http://archive.canonical.com/ubuntu xenial partner
```

There will be some offending lines, but in order to fix this delete them, as this is a example using the repo sources generator. To be more precise, you just need the following lines:

```bash
# repos
deb http://ports.ubuntu.com/ubuntu-ports/ xenial main universe multiverse restricted
deb-src http://ports.ubuntu.com/ubuntu-ports/ xenial main universe  multiverse restricted
deb http://ports.ubuntu.com/ubuntu-ports/ xenial-updates main
deb-src http://ports.ubuntu.com/ubuntu-ports/ xenial-updates main
deb http://ports.ubuntu.com/ubuntu-ports/ xenial-security main
deb-src http://ports.ubuntu.com/ubuntu-ports/ xenial-security main

```

After this stage, you'll need to update your cache, so upgrade as you usually do on your desktop computer:

```bash
sudo apt-get update           # update cache
sudo apt-get upgrade -y       # update packages
sudo apt-get upgrade-dist -y  # upgrade distro to latest version
sudo apt autoremove           # clean and free some space
sudo apt install update-manager-core # needed to upgrade (if you didn't installed previously)
```

The earlier process is not automated as apt will ask about changing some files. There is no harm on agree with it.

Make sure that your `/etc/update-manager/release-upgrades` file points to a `lts` version of the distro (you don't want to face this problem again in the near future I suppose).

Then, you should be able to perform:

```bash
sudo do-release-upgrade # now it will update to the latest version 18.04
```

This whole process will last for about an hour. So, in order to get a copy of your data, use this command to get a compressed image of your SD card:

```bash
# here /dev/mmcblk0 is my sd card reader device, change it accordingly
sudo dd if=/dev/mmcblk0 | gzip > paralella_ubuntu_18.04.img.gz 
```

## Downloadable image

Requirements:
*  An SDcard with  >= 4GB of free space

Considerations:
* There will be a bunch of trash since I had to clean my installation before zipping it, but it wouldn't affect it's use
* Intented for the z7010 version. (DO NOT USE IT ON THE z7020).
* No E-Link support, as I use it for FPGA development (yes, you can, it's more complex than an ArtyZ7 but you can actually use it with Vivado HLS, maybe I'll post a tutorial next week about how to do it).

Link: [parabuntu_18.04.img.gz](https://drive.google.com/file/d/1gSjX_swWaxb3z89N6akXqd9zNe8q7Fy_/view?usp=sharing)


Bye~~