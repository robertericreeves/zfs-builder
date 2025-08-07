#!/bin/bash
#
# Copyright The Titan Project Contributors.
#

#
# WSL2 ZFS Build Process - Custom Kernel Approach
# 
# WSL2 requires ZFS to be statically compiled into the kernel, not loaded as modules.
# This approach builds a complete custom WSL2 kernel with ZFS built-in.
#
# Based on: https://github.com/alexhaydock/zfs-on-wsl
#

KERNELSUFFIX="titan-zfs"
KERNELDIR="/opt/wsl2-kernel"
ZFSDIR="/opt/wsl2-zfs"

# Install build dependencies
function install_dependencies() {
    echo "Installing WSL2 kernel build dependencies..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        autoconf \
        automake \
        bc \
        bison \
        build-essential \
        curl \
        dkms \
        flex \
        git \
        libaio-dev \
        libattr1-dev \
        libblkid-dev \
        libelf-dev \
        libffi-dev \
        libssl-dev \
        libtirpc-dev \
        libtool \
        libudev-dev \
        python3 \
        python3-cffi \
        python3-dev \
        python3-setuptools \
        uuid-dev \
        zlib1g-dev \
        dwarves
}

# Get WSL2 kernel source 
function get_kernel_src() {
    local version=$KERNEL_VERSION

    echo "Fetching Microsoft WSL2 kernel source..."
    
    # Create kernel directory
    mkdir -p $KERNELDIR
    
    # Get the latest WSL2 kernel version that matches our running kernel
    # For WSL2, we want to build against the same version we're running
    UPSTREAMKERNELVER=$(echo $KERNEL_RELEASE | sed 's/-microsoft-standard-WSL2//')
    
    # Try to find matching release tag
    WSL2_TAG=$(curl -s https://api.github.com/repos/microsoft/WSL2-Linux-Kernel/releases | \
        jq -r ".[] | select(.tag_name | contains(\"$UPSTREAMKERNELVER\")) | .tag_name" | head -n1)
    
    if [ -z "$WSL2_TAG" ]; then
        # Fallback to latest release
        WSL2_TAG=$(curl -s https://api.github.com/repos/microsoft/WSL2-Linux-Kernel/releases/latest | \
            jq -r '.tag_name')
    fi
    
    echo "Using WSL2 kernel version: $WSL2_TAG"
    
    # Clone Microsoft kernel source if not exists
    if [ ! -d $KERNELDIR/.git ]; then
        echo "Cloning Microsoft WSL2 kernel..."
        git clone --branch $WSL2_TAG --single-branch --depth 1 \
            https://github.com/microsoft/WSL2-Linux-Kernel.git $KERNELDIR
    else
        echo "Updating existing kernel source..."
        cd $KERNELDIR
        git reset --hard && git checkout $WSL2_TAG && git pull
    fi
    
    KERNEL_SRC=$KERNELDIR
    KERNEL_OBJ=$KERNELDIR
}

# Prepare kernel source for ZFS compilation
function prepare_kernel() {
    echo "Preparing kernel source for ZFS compilation..."
    
    cd $KERNELDIR
    
    # Get the kernel config from current running WSL2 kernel
    echo "Copying current kernel configuration..."
    if [ -f /proc/config.gz ]; then
        zcat /proc/config.gz > .config
    else
        echo "Warning: /proc/config.gz not found, using default config"
        make defconfig
    fi
    
    # Run make prepare to generate necessary headers
    echo "Running make prepare to generate kernel headers..."
    make prepare
    
    # Run make scripts to build host tools
    echo "Building kernel scripts..."
    make scripts
}

# Get ZFS source for built-in compilation
function get_zfs_builtin() {
    echo "Fetching OpenZFS source for built-in compilation..."
    
    # Create ZFS directory
    mkdir -p $ZFSDIR
    
    # Use same ZFS version as configured for Titan
    UPSTREAMZFSVER=${ZFS_VERSION:-zfs-2.1.5}
    
    # Clone ZFS source if not exists
    if [ ! -d $ZFSDIR/.git ]; then
        echo "Cloning OpenZFS repository..."
        git clone --branch $UPSTREAMZFSVER --depth 1 \
            https://github.com/zfsonlinux/zfs.git $ZFSDIR
    else
        echo "Updating existing ZFS source..."
        cd $ZFSDIR
        git reset --hard && git checkout $UPSTREAMZFSVER && git pull
    fi
}

# Configure ZFS for built-in kernel compilation
function configure_zfs_builtin() {
    echo "Configuring ZFS for built-in kernel compilation..."
    
    cd $ZFSDIR
    
    # Generate configure script
    sh autogen.sh
    
    # Configure ZFS for built-in compilation
    ./configure \
        --prefix=/ \
        --libdir=/lib \
        --includedir=/usr/include \
        --datarootdir=/usr/share \
        --enable-linux-builtin=yes \
        --with-linux=$KERNELDIR \
        --with-linux-obj=$KERNELDIR
    
    # Copy ZFS source into kernel tree
    echo "Copying ZFS source into kernel tree..."
    ./copy-builtin $KERNELDIR
    
    # Build and install userspace utilities
    echo "Building ZFS userspace utilities..."
    make -j "$(nproc)"
    make install
}

# Build WSL2 kernel with ZFS built-in
function build_kernel() {
    echo "Building WSL2 kernel with ZFS built-in..."
    
    cd $KERNELDIR
    
    # Update kernel config with WSL2 defaults and enable ZFS
    export KCONFIG_CONFIG="Microsoft/config-wsl"
    
    # Enable USB storage support (useful for ZFS testing)
    echo "CONFIG_USB_STORAGE=y" >> "$KCONFIG_CONFIG"
    
    # Enable ZFS as built-in module
    echo "CONFIG_ZFS=y" >> "$KCONFIG_CONFIG"
    
    # Prepare kernel configuration
    make olddefconfig
    make prepare
    make scripts
    
    # Build the kernel
    echo "Compiling kernel (this may take 30+ minutes)..."
    echo "Starting kernel compilation at: $(date)"
    
    # Start a background process to output progress every 2 minutes
    (
        while true; do
            sleep 120
            if [ -f /tmp/kernel_build_complete ]; then
                break
            fi
            echo "Kernel build still in progress... $(date)"
        done
    ) &
    PROGRESS_PID=$!
    
    # Build kernel with verbose output to show progress
    make -j "$(nproc)" LOCALVERSION="-$KERNELSUFFIX" V=1
    
    # Signal that build is complete
    touch /tmp/kernel_build_complete
    kill $PROGRESS_PID 2>/dev/null || true
    
    echo "Kernel compilation completed at: $(date)"
    
    # Copy kernel to output location
    echo "Kernel build complete!"
    echo "Built kernel: arch/x86/boot/bzImage"
    
    # Make kernel available in /out for extraction
    mkdir -p /out
    cp arch/x86/boot/bzImage /out/bzImage-$KERNEL_RELEASE-$KERNELSUFFIX
    
    # Also try to save directly to Windows filesystem if volume is mounted
    if [ -d /mnt/c/ZFSonWSL ]; then
        echo "Saving kernel directly to Windows filesystem..."
        cp arch/x86/boot/bzImage /mnt/c/ZFSonWSL/bzImage-$KERNEL_RELEASE-$KERNELSUFFIX
        cp arch/x86/boot/bzImage /mnt/c/ZFSonWSL/bzImage
        echo "Kernel saved to: C:\\ZFSonWSL\\bzImage"
    elif [ -d /host/ZFSonWSL ]; then
        echo "Saving kernel to host volume..."
        cp arch/x86/boot/bzImage /host/ZFSonWSL/bzImage-$KERNEL_RELEASE-$KERNELSUFFIX
        cp arch/x86/boot/bzImage /host/ZFSonWSL/bzImage
        echo "Kernel saved to host volume: /host/ZFSonWSL/bzImage"
    fi
    
    echo "Custom WSL2 kernel with ZFS available at: /out/bzImage-$KERNEL_RELEASE-$KERNELSUFFIX"
    echo ""
    echo "To use this kernel:"
    echo "1. Copy the kernel to Windows: /mnt/c/ZFSonWSL/bzImage"
    echo "2. Add to .wslconfig:"
    echo "   [wsl2]"
    echo "   kernel=C:\\\\ZFSonWSL\\\\bzImage"
    echo "3. Run: wsl --shutdown"
    echo "4. Restart WSL2"
}

# Check if ZFS is already available in kernel
function check_zfs_availability() {
    echo "Checking if ZFS kernel support is already available..."
    
    # Check if ZFS filesystem is supported in kernel
    if grep -q "^nodev.*zfs" /proc/filesystems 2>/dev/null; then
        echo "✓ ZFS kernel support detected in /proc/filesystems"
        echo "🎉 ZFS is built into the kernel! No kernel build needed."
        echo "Current kernel: $(uname -r)"
        echo "ZFS filesystem support: AVAILABLE"
        return 0
    else
        echo "✗ ZFS kernel support not found in /proc/filesystems"
        echo "⚠️  ZFS kernel build required."
        return 1
    fi
}

# Main build function
function build() {
    echo "Starting WSL2 ZFS kernel support check..."
    
    # First check if ZFS kernel support is already available
    if check_zfs_availability; then
        echo "ZFS kernel support already available - skipping kernel build"
        return 0
    fi
    
    echo "Starting WSL2 custom kernel build with ZFS..."
    
    install_dependencies
    get_kernel_src
    prepare_kernel
    get_zfs_builtin
    configure_zfs_builtin
    build_kernel
    
    echo "WSL2 kernel with ZFS build complete!"
}
