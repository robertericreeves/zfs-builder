#
# Copyright The Titan Project Contributors.
#

# Used to create titandata/zfs-builder:latest. Until we update Docker Hub, use this locally to build titandata/zfs-builder:latest container.

FROM ubuntu:bionic

ARG KERNEL_RELEASE=
ARG KERNEL_UNAME=
ARG ZFS_VERSION=

RUN apt-get update

# Tools to fetch and build source
RUN apt-get install -y                                                       \
    git	                                                                     \
    curl xz-utils jq                                                         \
    build-essential bc                                                       \
    autoconf automake libtool kmod                                           \
    zlib1g-dev uuid-dev libattr1-dev libblkid-dev libselinux-dev libudev-dev \
    libacl1-dev libaio-dev libdevmapper-dev libssl-dev libelf-dev

# Python is not strictly required for ZFS, but eliminates a number of warnings
RUN apt-get install -y                                                       \
    python3 python3-distutils

# Linuxkit binaries (such as fixdep) require musl
RUN apt-get install -y musl

# Tar can fail sometimes on overlayfs, use bsdtar as a workaround
RUN apt-get install -y bsdtar

# Add required tools for kernel building and WSL2 custom kernel compilation
RUN apt-get install -y build-essential libncurses-dev bison flex libssl-dev   \
    libelf-dev dwarves python3-cffi python3-dev python3-setuptools           \
    libtirpc-dev libffi-dev

# Some distros require the ability to copy data from docker images
RUN apt-get -y install apt-transport-https \
     ca-certificates \
     curl \
     gnupg2 \
     software-properties-common
RUN curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg > /tmp/dkey; apt-key add /tmp/dkey
RUN add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") \
   $(lsb_release -cs) \
   stable"
RUN apt-get update
RUN apt-get -y install docker-ce

RUN mkdir /src
RUN mkdir /build
RUN mkdir /out

COPY src/* /

CMD /build.sh
